import 'package:flutter/foundation.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/store/clip_document.dart';
import '../../domain/midi/transforms/agent_spawn_transform.dart';
import '../../domain/midi/transforms/domain_subscription_transform.dart';
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
    required this.address,
    required this.host,
    required MidiTransformChain chain,
    ClipEditor? editor,
    MidiGraphController? graphController,
  }) : _chain = chain,
       editor = editor ?? ClipEditor(chain.source),
       graphController =
           graphController ?? MidiGraphController.seededFrom(chain);

  /// The clip entity this session plays/edits. `null` for the engine's default
  /// boot session, which exists before any project clip is opened.
  final EntityAddress? address;

  /// The shared engine pieces this session borrows for playback.
  final ClipSessionHost host;

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

  /// Name of the domain clock this session's transport binds to. One session,
  /// one clock; disposed with the transport. Per-session unique clock allocation
  /// arrives with concurrent playback (next issue); a single clip only ever runs
  /// one clock at a time.
  static const String _clockName = 'phi.midi.default';

  /// The note-list instance last pushed to the transport, by identity. The
  /// memoised [_playbackNotes] returns the *same* instance between changes, so a
  /// differing instance is exactly the "revision bumped" signal (issue #56) — the
  /// tick re-pushes when it sees one.
  List<MidiNote>? _pushedNotes;

  final ValueNotifier<double> _playhead = ValueNotifier<double>(0);

  /// Position of the playhead within the clip, in beats `[0, totalBeats)`. `0`
  /// while stopped. A frame-rate query of the engine clock's beat position
  /// (issue #103), not a Dart accumulator. The piano-roll painter binds to this.
  ValueListenable<double> get playhead => _playhead;

  bool _playing = false;

  /// Whether this session's transport is currently running.
  bool get isPlaying => _playing;

  /// The engine clock's beat position captured at [play] (issue #103). Play is
  /// relative to it, so `transport.beatPosition - _originBeat` is the beats
  /// elapsed since play across loop boundaries.
  double _originBeat = 0;

  /// End of the last Scene-spawn window, in play-relative beats. `0` at [play].
  double _prevBeat = 0;

  /// The tempo last pushed to the transport clock, so re-application is a no-op
  /// when the effective tempo hasn't moved. `null` until the first application.
  double? _appliedTempo;

  /// Notes currently sounding, by `(channel, pitch)`, so the session releases
  /// exactly what it pressed if a transform overlaps voices.
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
    // Mint the transport now the port is open, bind the clock to the effective
    // tempo, push the current output, and let the engine own note timing.
    final transport = _transport ??= host.gateway.createTransport(
      clockName: _clockName,
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

  /// Stop playback, silence any sounding notes, and rewind the playhead. No-op
  /// if not playing. Returns `true` if this call actually stopped playback.
  ///
  /// Clearing the shared scene field is the **manager's** concern (agents are a
  /// shared resource, keyed per voice), so this touches only the session's own
  /// transport, sounding set, and playhead.
  bool stop() {
    if (!_playing) return false;
    _playing = false;
    _transport?.stop();
    host.gateway.allNotesOff();
    _sounding.clear();
    _pushedNotes = null;
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
    // when the interpretation changed. Re-push then, so the engine swaps its
    // event buffer at the next block.
    if (!identical(_playbackNotes, _pushedNotes)) pushEvents();
    // The window drives the Scene agent field only — note *sound* is the engine
    // transport's job now.
    _dispatchWindow(_prevBeat, now);
    _prevBeat = now;
    final total = _chain.source.totalBeats;
    _playhead.value = total > 0 ? now % total : now;
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
  }

  // ─── note dispatch ──────────────────────────────────────────────────────

  /// Flatten the interpreted notes into [TransportNote]s and push them (with the
  /// loop length) to the engine transport. Resolves each fractional pitch to its
  /// nearest semitone and, in microtonal mode, carries the leftover cents as
  /// normalised pitch-bend event data. Records the pushed instance so [advance]
  /// can tell an unchanged output from a genuine revision bump.
  void pushEvents() {
    final notes = _playbackNotes;
    _pushedNotes = notes;
    final total = _chain.source.totalBeats;
    final microtonal = host.microtonal;
    final events = <TransportNote>[
      for (final note in notes)
        TransportNote(
          startBeat: note.start,
          durationBeats: note.duration,
          channel: note.channel,
          pitch: _semitoneOf(note),
          velocity: note.velocity.clamp(0.0, 1.0).toDouble(),
          pitchBend: microtonal ? _bendFor(note, _semitoneOf(note)) : 0.0,
        ),
    ];
    _transport?.setEvents(events, loopBeats: total);
  }

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
    _sounding.add(_voiceKey(note.channel, semitone));
    _spawnAgent(note, semitone);
  }

  void _noteOff(MidiNote note) {
    final semitone = _semitoneOf(note);
    final key = _voiceKey(note.channel, semitone);
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
      _voiceKey(note.channel, semitone),
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

  int _voiceKey(int channel, int pitch) => channel * 128 + pitch;

  static const double _bendRangeSemitones = 2.0; // GM default: ±2 semitones.

  /// Release the transport, playhead, graph controller, editor and chain this
  /// session owns. Silencing the shared output is the manager's concern.
  void dispose() {
    if (_playing) {
      _transport?.stop();
      _playing = false;
    }
    _transport?.dispose();
    _transport = null;
    _playhead.dispose();
    graphController.dispose();
    editor.dispose();
    _chain.dispose();
  }
}
