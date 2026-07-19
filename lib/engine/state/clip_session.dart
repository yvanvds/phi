import 'package:flutter/foundation.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/store/clip_document.dart';
import '../../domain/midi/transforms/agent_spawn_transform.dart';
import '../../domain/midi/transforms/domain_subscription_transform.dart';
import '../../domain/midi/voice_hash.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/scene/scene_agent.dart';
import '../bridge/midi_transport.dart';
import '../bridge/transport_note.dart';
import 'clip_session_host.dart';
import 'midi_graph_controller.dart';

/// One clip's live playback + authoring bundle (issue #186).
///
/// Extracted from [EngineMidiController], which held exactly these pieces
/// globally before this refactor: the source clip + linear pipeline in a
/// [MidiTransformChain], the piano-roll edits in a [ClipEditor], the branching
/// interpretation in a [MidiGraphController], the engine [MidiTransport] the
/// interpreted notes are pushed to, and the **push-on-change** memoisation that
/// re-pushes only when the interpreted output actually changes (a clip edit,
/// chip toggle, hot-reload, or — graph mode — a state/variable flip). A session
/// is keyed by its clip [address] and borrows the engine's shared pieces (the
/// MIDI output, scene field, tempo stack, live graph context) through a
/// [ClipSessionHost].
///
/// The manager plays exactly one session at a time — the edited one — so the
/// single-clip flow is behaviour-identical to the pre-refactor controller. This
/// is the seam concurrency (the next issue) builds on: N sessions, each on its
/// own transport + domain clock, spawning side by side into the shared field.
///
/// Which transformed notes playback reads depends on the clip's
/// [MidiGraphController.mode] (issue #77): a **chain** clip reads the linear
/// [MidiTransformChain.output]; a **graph** clip reads the branching
/// [MidiTransformGraph]'s `evaluate` against the host's live [GraphEvalContext].
class ClipSession {
  ClipSession({
    required EntityAddress? address,
    required this.host,
    required MidiTransformChain chain,
    ClipEditor? editor,
    MidiGraphController? graphController,
    String clockName = defaultClockName,
    this.sceneKeyBase = 0,
    bool loop = true,
  }) : _address = address,
       _clockName = clockName,
       _chain = chain,
       _loop = loop,
       editor = editor ?? ClipEditor(chain.source),
       graphController =
           graphController ?? MidiGraphController.seededFrom(chain);

  EntityAddress? _address;

  /// The clip entity this session plays/edits. `null` for the engine's default
  /// boot session, which exists before any project clip is opened. Re-keyed once
  /// when the engine reconciles the boot session with the project's first clip on
  /// open (issue #197) — see [rekey].
  EntityAddress? get address => _address;

  /// The shared engine pieces this session borrows for playback.
  final ClipSessionHost host;

  String _clockName;

  /// Name of the domain clock this session's transport binds to. Unique per
  /// session — the manager derives it from [address] — so concurrent sessions
  /// each run on their own clock, the polytemporal shape (issue #187). Defaults
  /// to [defaultClockName] for a lone session that never runs beside another.
  /// Updated alongside the address when the boot session is reconciled ([rekey]).
  String get clockName => _clockName;

  /// Base offset for this session's scene-field voice keys, so concurrent
  /// sessions occupy disjoint key bands in the one shared [SceneField]: a note's
  /// key is [sceneKeyBase]` + voiceBucket * 128 + pitch`. The manager hands each
  /// session a distinct base (issue #187) so two clips spawn side by side and a
  /// stopped clip clears only its own agents. Defaults to `0` for a lone session.
  final int sceneKeyBase;

  final MidiTransformChain _chain;

  /// The transform chain this session reads (source clip → transforms →
  /// [MidiTransformChain.output]). Exposed so the surface binds its chip panel
  /// and ghost layer to the same instance.
  MidiTransformChain get chain => _chain;

  /// The shared authoring controller. Gestures on the piano roll edit the same
  /// clip this session reads.
  final ClipEditor editor;

  /// The branching transform-graph editor (issue #65), seeded from the chain so
  /// it opens on the working linear chain. Its [MidiGraphController.mode] decides
  /// whether playback reads the linear chain or this graph.
  final MidiGraphController graphController;

  /// The engine clip transport, minted lazily from the host gateway on first
  /// [play] (after the port is open) and reused across plays. `null` until then.
  MidiTransport? _transport;

  /// The default clock name for a lone session (the engine's boot session, or a
  /// [ClipSession] built without an explicit [clockName]). The manager overrides
  /// it per session so concurrent clips never share a clock.
  static const String defaultClockName = 'phi.midi.default';

  /// The note-list instance last pushed to the transport, by identity. The
  /// memoised [_playbackNotes] returns the *same* instance between changes, so a
  /// differing instance is exactly the "revision bumped" signal (issue #56) — the
  /// tick re-pushes when it sees one.
  List<MidiNote>? _pushedNotes;

  /// The loop length ([_loopBeats]) last pushed to the transport. A length edit
  /// (or auto-extend) mid-play moves the declared [MidiClip.totalBeats] without
  /// touching the note list — the note-identity check above never fires — yet the
  /// **audible** loop window must follow the new length (issue #200). [advance]
  /// re-pushes when this diverges from the current [_loopBeats]. `null` until the
  /// first push, and reset on [stop].
  double? _pushedLoopBeats;

  final ValueNotifier<double> _playhead = ValueNotifier<double>(0);

  /// Position of the playhead within the clip, in beats `[0, totalBeats)`. `0`
  /// while stopped. A frame-rate query of the engine clock's beat position
  /// (issue #103), not a Dart accumulator. The piano-roll painter binds to this.
  ValueListenable<double> get playhead => _playhead;

  bool _playing = false;

  /// Whether this session's transport is currently running. `false` while paused
  /// — the manager's frame ticker only advances playing sessions.
  bool get isPlaying => _playing;

  bool _paused = false;

  /// Whether this session is paused: its dispatch halted and its clock frozen,
  /// but its beat position kept so [resume] continues mid-loop. Distinct from
  /// stopped (which rewinds to the top) and from playing.
  bool get isPaused => _paused;

  bool _loop;

  /// Whether playback loops the clip's declared length ([MidiClip.totalBeats]).
  /// Loop off pushes `loopBeats <= 0`, so the events fire once (issue #184,
  /// wired into live playback in issue #187). Persisted per clip in its document;
  /// toggling it while playing (or paused) re-pushes the loop length live,
  /// without ever rewriting the note list.
  bool get loop => _loop;
  set loop(bool value) {
    if (_loop == value) return;
    _loop = value;
    if (_playing || _paused) pushEvents();
  }

  /// The engine clock's beat position captured at [play] (issue #103). Play is
  /// relative to it, so `transport.beatPosition - _originBeat` is the beats
  /// elapsed since play across loop boundaries.
  double _originBeat = 0;

  /// End of the last Scene-spawn window, in play-relative beats. `0` at [play].
  double _prevBeat = 0;

  /// The tempo last pushed to the transport clock, so re-application is a no-op
  /// when the effective tempo hasn't moved. `null` until the first application.
  double? _appliedTempo;

  /// Notes currently sounding, by scene key (`voiceBucket, pitch`), so the
  /// session releases exactly what it pressed if a transform overlaps voices.
  final Set<int> _sounding = <int>{};

  // ─── playback lifecycle ─────────────────────────────────────────────────

  /// Start (or restart) playback from the top of the clip. Opens the shared
  /// output port and mints the transport lazily on first play, then pushes the
  /// interpreted note list to it and lets the engine dispatch. No-op if already
  /// playing. Returns `true` if this call actually started playback.
  bool play() {
    if (_playing) return false;
    if (!host.gateway.isOpen) {
      final port = host.resolveOutputPort();
      if (port != null) host.gateway.open(port);
    }
    _prevBeat = 0;
    _playhead.value = 0;
    _playing = true;
    _paused = false;
    // Mint the transport now the port is open, bind the clock to the effective
    // tempo, push the current output, and let the engine own note timing.
    final transport = _transport ??= host.gateway.createTransport(
      clockName: clockName,
      tempo: _effectiveTempo,
    );
    _appliedTempo = null;
    applyTempo();
    pushEvents();
    transport.play();
    // Anchor play to the free-running engine clock: read play-relative position
    // as `beatPosition - origin` (issue #103).
    _originBeat = transport.beatPosition;
    return true;
  }

  /// Pause playback: halt dispatch, silence any sounding voice with
  /// `allNotesOff`, and **freeze the bound clock** (tempo 0). Because a tempo-0
  /// clock does not advance (verified in dart-yse's `clock_clip_test`), the beat
  /// position — and the audible loop phase — hold across the pause, so [resume]
  /// continues mid-loop without depending on the clip transport re-anchoring
  /// across a stop/play. The beat origin and the frozen playhead are kept; only
  /// this session's own scene agents are cleared. No-op unless playing. Returns
  /// whether this call paused.
  bool pause() {
    if (!_playing) return false;
    _playing = false;
    _paused = true;
    // Freeze the clock so no beat elapses while paused. Paused sessions are never
    // ticked and a tempo/fader change skips them, so nothing fights the freeze
    // until [resume] restores the rate.
    _transport?.setTempo(0);
    _appliedTempo = 0;
    host.gateway.allNotesOff();
    _clearOwnAgents();
    return true;
  }

  /// Resume from a [pause]: restore the effective tempo (un-freezing the clock)
  /// and let dispatch run on. Because the clock held its beat while paused, the
  /// play-relative position resumes exactly where it left off — no beat is
  /// skipped over the pause. No-op unless paused. Returns whether this call
  /// resumed.
  bool resume() {
    if (!_paused) return false;
    _paused = false;
    _playing = true;
    _appliedTempo = null;
    applyTempo();
    _transport?.play();
    return true;
  }

  /// Stop playback (from playing or paused), silence any sounding notes, clear
  /// this session's own scene agents, and rewind the playhead. No-op if already
  /// stopped. Returns `true` if this call actually stopped playback.
  ///
  /// Only this session's own agents are cleared — keyed in its [sceneKeyBase]
  /// band — so a stop leaves concurrent clips (and the scene demo) untouched
  /// (issue #187). The rest of the shared field stays the manager's concern.
  bool stop() {
    if (!_playing && !_paused) return false;
    _playing = false;
    _paused = false;
    _transport?.stop();
    host.gateway.allNotesOff();
    _clearOwnAgents();
    _pushedNotes = null;
    _pushedLoopBeats = null;
    _originBeat = 0;
    _prevBeat = 0;
    _playhead.value = 0;
    return true;
  }

  /// Push [_effectiveTempo] to the transport clock when it changed. Called on
  /// play, each tick, and on a session-tempo / fader change — so toggling the
  /// domain chip (or editing the subscribed domain's tempo) re-binds the clock
  /// live, without ever re-pushing the note list. Idempotent between changes.
  void applyTempo() {
    final tempo = _effectiveTempo;
    if (tempo == _appliedTempo) return;
    _appliedTempo = tempo;
    _transport?.setTempo(tempo);
  }

  /// Advance the session by [dtSeconds] of frame time (issue #103): query the
  /// engine clock for the play-relative beat, re-push on change, cross the Scene
  /// window, and move the playhead. A no-op when not playing. The shared field's
  /// per-frame [SceneField.step] is stepped once by the manager after every
  /// session has advanced.
  void advance(double dtSeconds) {
    if (!_playing) return;
    final now = (_transport?.beatPosition ?? 0) - _originBeat;
    // Push-on-change: the memoised output hands back a new list instance only
    // when the interpretation changed, and [_loopBeats] moves only when the
    // declared length was edited — a length edit / auto-extend leaves the note
    // list identity intact, so the loop window changed on its own (issue #200).
    // Re-push on either, so the engine swaps its event buffer — and its loop
    // length — at the next block.
    if (!identical(_playbackNotes, _pushedNotes) ||
        _loopBeats != _pushedLoopBeats) {
      pushEvents();
    }
    // The window drives the Scene agent field only — note *sound* is the engine
    // transport's job now.
    _dispatchWindow(_prevBeat, now);
    _prevBeat = now;
    final total = _chain.source.totalBeats;
    _playhead.value = total > 0 ? now % total : now;
  }

  /// Re-key this session to [address], binding its transport to [clockName]
  /// (issue #197). The engine promotes the boot session (keyed `null`) to the
  /// project's first clip on open, so the panel's later selection of that clip
  /// reuses this very session — with its live chain / editor / graph and any
  /// already-bound surfaces — rather than minting an address-keyed duplicate
  /// beside it. Intended before this session's transport is minted (the clock
  /// name is read at first [play]); the boot reconciliation always runs at open,
  /// before any play.
  void rekey({required EntityAddress address, required String clockName}) {
    _address = address;
    _clockName = clockName;
  }

  /// Adopt a loaded [document] into the live clip objects **in place** (issue
  /// #139) — the source clip, chain, editor and graph controller are mutated
  /// rather than recreated, so every surface already bound to these instances
  /// follows the swap without re-wiring:
  /// - the shared source clip's notes + meter are replaced;
  /// - the [ClipEditor]'s undo history is reset (its indices no longer apply);
  /// - the linear chain adopts the document's transform list;
  /// - the graph controller is re-seeded from the document's [ClipDocument.graph]
  ///   (or from the fresh chain when the document is chain-only) and its
  ///   [MidiGraphController.mode] set to the document's mode.
  ///
  /// The [document]'s transforms are expected already re-resolved / re-linked by
  /// the codec that decoded it. While playing, the tick's push-on-change picks up
  /// the fresh output within one frame; adoption normally runs on a stopped
  /// transport at open.
  void adopt(ClipDocument document) {
    _chain.source.replaceWith(document.source);
    editor.reset();
    _chain.setTransforms(document.chain);
    final graph = document.graph;
    if (graph != null) {
      graphController.loadFromGraph(graph);
    } else {
      graphController.loadFromChain(_chain);
    }
    graphController.mode = document.mode;
    _loop = document.loop;
  }

  // ─── note dispatch ──────────────────────────────────────────────────────

  /// Flatten the interpreted notes into [TransportNote]s and push them (with the
  /// loop length) to the engine transport. Resolves each fractional pitch to its
  /// nearest semitone and, in microtonal mode, carries the leftover cents as
  /// normalised pitch-bend event data. Records the pushed instance so [advance]
  /// can tell an unchanged output from a genuine revision bump.
  ///
  /// Each note's routed voice is mapped to its allocated engine channel (design
  /// `docs/design/racks-and-voices.md` §6). A note whose voice resolves to no
  /// known channel is **skipped** (it plays nothing) and its voice reported to
  /// the host once, so an unknown voice degrades gracefully rather than crashing.
  void pushEvents() {
    final notes = _playbackNotes;
    _pushedNotes = notes;
    final loopBeats = _loopBeats;
    _pushedLoopBeats = loopBeats;
    final microtonal = host.microtonal;
    final events = <TransportNote>[];
    Set<String>? unresolved;
    for (final note in notes) {
      final channel = host.channelForVoice(note.voice);
      if (channel == null) {
        // An unknown voice: silent, but surfaced. (An unrouted note — null
        // voice — always resolves through the default voice, so it never lands
        // here.)
        (unresolved ??= <String>{}).add(note.voice!);
        continue;
      }
      final semitone = _semitoneOf(note);
      events.add(
        TransportNote(
          startBeat: note.start,
          durationBeats: note.duration,
          channel: channel,
          pitch: semitone,
          velocity: note.velocity.clamp(0.0, 1.0).toDouble(),
          pitchBend: microtonal ? _bendFor(note, semitone) : 0.0,
        ),
      );
    }
    final reported = unresolved;
    if (reported != null) {
      for (final voice in reported) {
        host.onUnresolvedVoice(voice);
      }
    }
    // Loop off pushes `loopBeats <= 0`, so the engine fires the events once and
    // stops (issue #184/#187); loop on loops the clip's declared length.
    _transport?.setEvents(events, loopBeats: loopBeats);
  }

  /// The loop length the transport should run at: the clip's declared
  /// [MidiClip.totalBeats] when looping, else `0` for a one-shot (issue
  /// #184/#187). Tracked against [_pushedLoopBeats] so [advance] re-pushes when a
  /// mid-play length edit moves it, even though the note list keeps its identity
  /// (issue #200).
  double get _loopBeats => _loop ? _chain.source.totalBeats : 0;

  /// The transformed notes playback reads this tick, chosen by the clip's
  /// [MidiGraphController.mode]: the linear [MidiTransformChain.output] for a
  /// chain clip, or the branching graph's `evaluate` against the host's live
  /// context for a graph clip. Both are memoised, so reading every tick is an
  /// O(1) hit between edits (and, for the graph, between state flips).
  List<MidiNote> get _playbackNotes =>
      graphController.mode == MidiClipMode.graph
      ? graphController.graph.evaluate(host.liveContext())
      : _chain.output;

  /// The clip's **base** tempo before any played steering: the tempo of the
  /// first **active** [DomainSubscriptionTransform] that resolves a domain (a
  /// subscription binds the clock — issue #102), or the host session tempo when
  /// no clip is subscribed.
  double get _baseTempo {
    for (final t in _chain.transforms) {
      if (t is DomainSubscriptionTransform && t.active) {
        final bound = t.boundTempo;
        if (bound != null) return bound;
      }
    }
    return host.sessionBpm;
  }

  /// The tempo the transport clock should run at: the [_baseTempo] bent by the
  /// shared tempo-source seam (issue #104). With every source at rest the seam is
  /// the identity. Like the subscription, this only chooses the clock rate — it
  /// never rewrites note times, so bending tempo never forces a re-push.
  double get _effectiveTempo => host.tempoSources.apply(_baseTempo);

  /// Cross the Scene agent field over every note whose absolute beat falls in
  /// `[from, to)`. Note events repeat every `totalBeats` (the clip loops), so the
  /// same source event is mapped into each loop iteration the window spans.
  ///
  /// This drives the *Scene* only — a note-on spawns an agent, its note-off
  /// despawns it. The audible notes are the engine transport's job.
  void _dispatchWindow(double from, double to) {
    if (host.agentSink == null) return;
    final total = _chain.source.totalBeats;
    final notes = _playbackNotes;
    if (total <= 0 || notes.isEmpty) return;

    final firstLoop = (from / total).floor();
    final lastLoop = (to / total).floor();
    for (var loop = firstLoop; loop <= lastLoop; loop++) {
      final base = loop * total;
      for (final note in notes) {
        final onAt = base + note.start;
        if (onAt >= from && onAt < to) _noteOn(note);
        final offAt = base + note.start + note.duration;
        if (offAt >= from && offAt < to) _noteOff(note);
      }
    }
  }

  void _noteOn(MidiNote note) {
    final semitone = _semitoneOf(note);
    _sounding.add(_voiceKey(voiceHash(note.voice) % 16, semitone));
    _spawnAgent(note, semitone);
  }

  void _noteOff(MidiNote note) {
    final semitone = _semitoneOf(note);
    final key = _voiceKey(voiceHash(note.voice) % 16, semitone);
    if (!_sounding.remove(key)) return;
    _despawnAgent(key);
  }

  /// Spawn a live scene agent for [note] when a Scene sink is wired and an active
  /// [AgentSpawnTransform] is in the chain. The agent lives until the matching
  /// note-off ([_despawnAgent]).
  void _spawnAgent(MidiNote note, int semitone) {
    final sink = host.agentSink;
    if (sink == null) return;
    final transform = _activeSpawnTransform;
    if (transform == null) return;
    final spawn = transform.spawnFor(note);
    host.field.spawn(
      _voiceKey(voiceHash(note.voice) % 16, semitone),
      SceneAgent(
        position: spawn.position,
        velocity: spawn.velocity,
        voiceIndex: spawn.voiceIndex,
      ),
    );
    sink.setAgents(host.field.agents);
  }

  /// Despawn the agent a note-on left under [key], if any, and push the updated
  /// set to the sink.
  void _despawnAgent(int key) {
    if (!host.field.despawn(key)) return;
    host.agentSink?.setAgents(host.field.agents);
  }

  /// Despawn every scene agent this session spawned — its own [sceneKeyBase]
  /// band — from the shared field and push the survivors to the sink, then clear
  /// the sounding set. A stop or pause clears only this clip's agents, leaving
  /// concurrent clips (and the scene demo) untouched (issue #187). A no-op when
  /// this session has nothing sounding.
  void _clearOwnAgents() {
    if (_sounding.isEmpty) return;
    var changed = false;
    for (final key in _sounding) {
      if (host.field.despawn(key)) changed = true;
    }
    _sounding.clear();
    if (changed) host.agentSink?.setAgents(host.field.agents);
  }

  /// The first active [AgentSpawnTransform] in the chain, or `null` if none — so
  /// toggling the spawn chip off (or removing it) stops driving the Scene.
  AgentSpawnTransform? get _activeSpawnTransform {
    for (final t in _chain.transforms) {
      if (t is AgentSpawnTransform && t.active) return t;
    }
    return null;
  }

  /// The integer MIDI pitch a note is voiced on — the semitone it rounds to.
  int _semitoneOf(MidiNote note) => note.pitch.round().clamp(0, 127);

  /// Normalised pitch-bend in `[-1, 1]` that voices [note]'s leftover cents (its
  /// distance from [semitone]). `±1` maps to the assumed ±2-semitone bend range.
  double _bendFor(MidiNote note, int semitone) {
    final semitonesOff = note.pitch - semitone;
    return (semitonesOff / _bendRangeSemitones).clamp(-1.0, 1.0);
  }

  /// This session's scene-field key for a `(voiceBucket, pitch)` pair, offset
  /// into its own [sceneKeyBase] band so concurrent sessions never collide on
  /// the one shared field (issue #187). The bucket is `voiceHash(voice) % 16`,
  /// keeping the key in the same `0..2047` span the old channel did.
  int _voiceKey(int bucket, int pitch) => sceneKeyBase + bucket * 128 + pitch;

  static const double _bendRangeSemitones = 2.0; // GM default: ±2 semitones.

  /// Release the transport, playhead, graph controller, editor and chain this
  /// session owns. Silencing the shared output is the manager's concern.
  void dispose() {
    if (_playing || _paused) {
      _transport?.stop();
      _playing = false;
      _paused = false;
    }
    _transport?.dispose();
    _transport = null;
    _playhead.dispose();
    graphController.dispose();
    editor.dispose();
    _chain.dispose();
  }
}
