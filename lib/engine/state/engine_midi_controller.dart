import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/graph/graph_eval_context.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/store/clip_document.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/scene/effect_volume.dart';
import '../../domain/scene/pick_ray.dart';
import '../../domain/scene/scatter.dart';
import '../../domain/scene/scene_demo.dart';
import '../../domain/scene/scene_field.dart';
import '../../domain/state_machine/slices/clip_slice_entry.dart';
import '../../domain/time_domains/fader_tempo_source.dart';
import '../../domain/time_domains/tempo_source_stack.dart';
import '../../domain/voice/voice_channel_resolver.dart';
import '../bridge/materialised_synth.dart';
import '../bridge/midi_gateway.dart';
import '../bridge/midi_input_event.dart';
import '../bridge/midi_transport.dart';
import '../bridge/scene_agent_sink.dart';
import 'clip_session.dart';
import 'clip_session_host.dart';
import 'count_in_controller.dart';
import 'midi_graph_controller.dart';
import 'record_controller.dart';
import 'state_machine_controller.dart';

/// Engine-side **session manager** for the MIDI surface (issue #186).
///
/// Before this refactor the controller held exactly one clip's worth of state —
/// one chain, one editor, one graph, one transport — globally. It now generalises
/// into a manager of [ClipSession]s: each session bundles its own clip + chain +
/// editor + graph + transport + push-on-change memoisation (keyed by entity
/// address), while the manager owns the genuinely **shared** pieces — the MIDI
/// output gateway, the 3D scene field and its agent sink, the global tempo-source
/// stack (the hand fader), and the live graph-evaluation context (state machine +
/// runtime variables). The manager exposes those to sessions through the
/// [ClipSessionHost] seam and drives the single frame ticker for all of them.
///
/// One session is **edited** at a time — the surface (ghost, graph canvas,
/// variables bar, preview strip, playhead) binds to it, exactly as it bound to
/// the single controller before. For now the manager also *plays* only the edited
/// session, so the single-clip flow is behaviour-identical to the pre-refactor
/// controller; concurrent playback across sessions is the next issue.
///
/// Note dispatch belongs to the engine, not the UI isolate (issue #101): on
/// [play] a session flattens its interpreted notes into a `TransportNote` list and
/// pushes it (with the loop length) to a `MidiTransport` bound to a domain clock,
/// and the engine fires every note from the audio thread. A frame ticker still
/// runs — for the display playhead, the Scene agent field, and to **re-push** on
/// change — and those frame-accurate concerns are **queries of the engine clock**
/// (issue #103), not a Dart-side integral.
class EngineMidiController implements ClipSessionHost {
  EngineMidiController({
    required MidiTransformChain chain,
    required this._gateway,
    ClipEditor? editor,
    this._agentSink,
    this._stateMachine,
    this._runtimeVariables,
    VoiceChannelResolver? voiceResolver,
    this._bpm = 120,
    this._outputPortName,
    this._microtonal = false,
    this._tickInterval = const Duration(milliseconds: 16),
  }) : _voiceResolver = voiceResolver ?? VoiceChannelResolver.seededDefault() {
    // The tempo-source seam (issue #104): the played tempo is each session's base
    // rate (its subscription or the session tempo) bent by the sum of the stack's
    // sources. The fader is the first source; re-ramp the playing sessions'
    // clocks whenever it (or any future source) moves.
    _tempoSources = TempoSourceStack([_tempoFader]);
    _tempoSources.addListener(_applyTempoToPlayingSessions);
    // The engine's default boot session, keyed off no entity address — the one
    // the surface binds to until a project clip is opened. `adoptDocument` swaps
    // its contents in place on project open so those bindings survive.
    final session = ClipSession(
      address: null,
      host: this,
      chain: chain,
      editor: editor,
      clockName: ClipSession.defaultClockName,
      // The boot session takes scene-key band 0, so a single-clip run keys its
      // voices exactly as before this refactor.
      sceneKeyBase: _allocateSceneKeyBase(),
    );
    _sessions[null] = session;
    _editedSession = session;
    // Record arm + capture flow (issue #261): drives a TakeRecorder against the
    // *edited* session off the gateway's parsed MIDI-in. The armed voice it tags
    // notes with is the racks audition path's, wired in by the shell.
    _record = RecordController(
      input: _gateway.inputEvents,
      target: () => _editedSession,
    );
  }

  final MidiGateway _gateway;

  late final RecordController _record;

  /// The record arm + capture flow for the edited session (issue #261). The
  /// transport row's record button drives its [RecordController.toggleArm]; the
  /// shell wires its [RecordController.armedVoice] to the racks audition path.
  RecordController get record => _record;

  final CountInController _countIn = CountInController();

  /// The count-in setting + scheduler (issue #263). The toolbar count-in picker
  /// binds to its [CountInController.bars]; [play] gates a fresh start on it,
  /// counting on a reserved clock at the edited session's tempo before playback
  /// (and any armed take) begins on the downbeat.
  CountInController get countIn => _countIn;

  /// The reserved clock the count-in measures against — minted lazily on the
  /// first counted play, paced to the edited session's tempo each time so the
  /// count counts on the session's own domain tempo (design §5). `null` until a
  /// count-in first runs; kept (stopped) between counts and disposed on [dispose].
  MidiTransport? _countClock;

  /// The reserved clock name the count-in transport binds to — distinct from any
  /// clip session's clock so counting never disturbs a running session.
  static const String countInClockName = 'phi.midi.countin';

  /// Optional Scene sink. When wired and a playing session's chain carries an
  /// active spawn transform, each note-on spawns a live agent (issue #37). `null`
  /// in setups without a Scene.
  final SceneAgentSink? _agentSink;

  /// The live state machine, mirrored into the graph's [GraphEvalContext] so a
  /// `state · break` edge opens exactly while that state is live. `null` in setups
  /// without a state machine — the graph then evaluates against the empty context.
  final StateMachineController? _stateMachine;

  /// The live runtime-variable registry, mirrored into the graph's
  /// [GraphEvalContext] (issue #78). `null` in setups without a registry.
  final RuntimeVariableRegistry? _runtimeVariables;

  final Duration _tickInterval;

  /// The clip sessions this manager owns, keyed by entity address; `null` keys
  /// the default boot session. Lazily grown by [openSession] and disposed
  /// together in [dispose].
  final Map<EntityAddress?, ClipSession> _sessions = {};

  /// Monotonic allocator for per-session scene-key bases (issue #187): each
  /// session gets a disjoint [ClipSession.sceneKeyBase] band, so concurrent
  /// clips never collide on the one shared [SceneField]. The boot session takes
  /// band `0`.
  int _nextSceneKeyBase = 0;

  /// Width of a session's scene-key band. Larger than any voice key
  /// (`voiceBucket * 128 + pitch` maxes at `15 * 128 + 127 = 2047`), so the
  /// bands never overlap.
  static const int _sceneKeyStride = 100000;

  int _allocateSceneKeyBase() {
    final base = _nextSceneKeyBase;
    _nextSceneKeyBase += _sceneKeyStride;
    return base;
  }

  /// The unique domain-clock name for the session at [address] (issue #187): the
  /// boot session (`null`) keeps [ClipSession.defaultClockName]; a project clip
  /// derives its clock name from its address, so concurrent clips each run on an
  /// independent clock.
  String _clockNameFor(EntityAddress? address) => address == null
      ? ClipSession.defaultClockName
      : 'phi.midi.${address.format()}';

  late ClipSession _editedSession;

  /// The session the surface binds to and the transport row drives — the clip
  /// currently open in the editor. Ghost painting, the graph canvas, the
  /// variables bar, the preview strip and the playhead all read from this.
  ClipSession get editedSession => _editedSession;

  /// The session for [address], or `null` when none is open for it.
  ClipSession? sessionFor(EntityAddress address) => _sessions[address];

  /// The clips slice of the live performance (design state-graph §4, issue
  /// #242): one entry per **playing** session with a clip entity address —
  /// edited or library, whatever is currently sounding — carrying the
  /// session's live loop flag. The boot session (no address) contributes
  /// nothing; paused and stopped sessions are not playing. This is what the
  /// state machine's capture-from-live seam reads.
  List<ClipSliceEntry> get playingClipEntries => [
    for (final session in _sessions.values)
      if (session.isPlaying && session.address != null)
        ClipSliceEntry(clip: session.address!, loop: session.loop),
  ];

  /// Open the clip entity at [address] as the edited session (design §3, §4):
  /// its session becomes the one the editor binds to. Reuses an already-open
  /// session for [address] (never re-adopting over live edits); otherwise creates
  /// one from [document] — source + linear chain, plus the branching graph and
  /// mode when the document carries them.
  ///
  /// This is the library-selection seam the panel UI (issue #188) drives when a
  /// performer picks a clip; the running single-clip app still swaps clip
  /// *contents* through [adoptDocument] in place.
  ClipSession openSession(EntityAddress address, ClipDocument document) {
    final session = ensureSession(address, document);
    if (!identical(_editedSession, session)) {
      _editedSession = session;
      // The edited session swapped — a library selection opened a different clip.
      // The owning engine rebinds the clip publisher so edits to *this* clip
      // persist into its own entity (issue #197).
      onEditedSessionChanged?.call();
    }
    return session;
  }

  /// Ensure a session exists for [address] **without** making it the edited one
  /// — the seam a library row's play / loop toggle uses to act on a clip other
  /// than the one open in the editor (issue #188). Reuses an already-open session
  /// (never re-adopting over live edits); otherwise builds one from [document].
  /// The edited session is untouched, so a row can start playing while a
  /// different clip stays open on the roll.
  ClipSession ensureSession(EntityAddress address, ClipDocument document) =>
      _sessions[address] ??= _buildSession(address, document);

  /// Builds a fresh [ClipSession] for [address] from [document] — source + linear
  /// chain, plus the branching graph and mode when the document carries them. The
  /// caller stores and (for [openSession]) marks it edited.
  ClipSession _buildSession(EntityAddress address, ClipDocument document) {
    final session = ClipSession(
      address: address,
      host: this,
      chain: MidiTransformChain(
        source: document.source,
        transforms: document.chain,
      ),
      clockName: _clockNameFor(address),
      sceneKeyBase: _allocateSceneKeyBase(),
      loop: document.loop,
    );
    final graph = document.graph;
    if (graph != null) session.graphController.loadFromGraph(graph);
    session.graphController.mode = document.mode;
    return session;
  }

  // ─── edited-session delegation (the pre-refactor controller surface) ──────

  /// The edited session's transform chain. Exposed so the surface binds its chip
  /// panel and ghost layer to the same instance.
  MidiTransformChain get chain => _editedSession.chain;

  /// The edited session's authoring controller. Gestures on the piano roll edit
  /// the clip this manager reads.
  ClipEditor get editor => _editedSession.editor;

  /// The edited session's branching transform-graph editor (issue #65). The MIDI
  /// surface binds both its node-and-cable canvas and the clip mode to this.
  MidiGraphController get graphController => _editedSession.graphController;

  /// The edited session's playhead — its beat position `[0, totalBeats)`, `0`
  /// while stopped. The piano-roll painter binds to this.
  ValueListenable<double> get playhead => _editedSession.playhead;

  /// Whether the edited session's transport is running.
  bool get isPlaying => _editedSession.isPlaying;

  /// Whether the edited session is paused (its clock frozen, position kept).
  bool get isPaused => _editedSession.isPaused;

  /// Start (or restart) playback of the edited session, then spin the frame
  /// ticker. No-op if already playing.
  ///
  /// A **fresh** start from stopped honours the count-in setting (issue #263):
  /// with `countIn.bars > 0` the click counts that many bars on a reserved clock
  /// at the session's tempo, and playback (with any armed take) begins on the
  /// downbeat — scheduled against the engine clock, not a Dart timer. A repeated
  /// press while a count runs is ignored; a session already playing or paused
  /// starts at once (a punch-in never waits — design §5).
  void play() {
    if (_countIn.isCounting) return;
    if (_editedSession.isPlaying ||
        _editedSession.isPaused ||
        !_beginCountIn()) {
      _startEditedPlayback();
      return;
    }
    // A count started: the frame ticker drives it to the downbeat.
    _syncTicker();
  }

  /// Start the edited session and any armed take at once — the body [play] runs
  /// on the downbeat (or immediately when no count-in is set).
  void _startEditedPlayback() {
    _editedSession.play();
    _record.onTransportPlay();
    _syncTicker();
  }

  /// Begin a count-in for a fresh play when `countIn.bars > 0`: mint/pace the
  /// reserved count clock, and schedule the downbeat against it at the edited
  /// clip's meter. Returns whether a count actually started (`false` when the
  /// setting is `0` — the caller then starts at once).
  bool _beginCountIn() {
    if (_countIn.bars <= 0) return false;
    final clock = _startCountClock();
    final began = _countIn.begin(
      beatsPerBar: _editedSession.clip.beatsPerBar,
      beatPosition: () => clock.beatPosition,
      onComplete: _completeCountIn,
    );
    if (!began) _stopCountClock();
    return began;
  }

  /// Mint (once) and start the reserved count clock, paced to the edited
  /// session's tempo so a count counts on the session's own domain tempo.
  MidiTransport _startCountClock() {
    final tempo = _editedSession.effectiveTempo;
    final clock = _countClock ??= _gateway.createTransport(
      clockName: countInClockName,
      tempo: tempo,
    );
    clock.setTempo(tempo);
    clock.play();
    return clock;
  }

  /// The count reached the downbeat — stop the count clock and start playback.
  void _completeCountIn() {
    _stopCountClock();
    _startEditedPlayback();
  }

  /// Halt the reserved count clock, keeping it for the next count.
  void _stopCountClock() => _countClock?.stop();

  /// Pause the edited session — halt its dispatch (`allNotesOff` so no voice
  /// hangs) and freeze its clock, keeping the beat position so [resume]
  /// continues mid-loop. Idles the ticker if nothing else needs it. No-op unless
  /// playing. Aborts a running count-in (there is nothing to pause yet).
  void pause() {
    if (_abortCountIn()) return;
    // End any take before the clock freezes, so held notes close at the real
    // beat (§3: pause ends the take, keeping its notes).
    _record.onTransportStop();
    if (!_editedSession.pause()) return;
    _syncTicker();
  }

  /// Resume the edited session from a [pause], then spin the frame ticker. No-op
  /// unless paused.
  void resume() {
    if (!_editedSession.resume()) return;
    _record.onTransportPlay();
    _syncTicker();
  }

  /// Stop the edited session's playback (clearing its own scene agents) and idle
  /// the ticker if nothing else needs it. No-op if already stopped. Concurrent
  /// clips and the scene demo are untouched — stopping a clip clears only its
  /// own agents (design §4).
  void stop() {
    // A stop during the count aborts it cleanly — nothing was playing yet, so
    // there is no take to close and no transport to rewind (design §5).
    if (_abortCountIn()) return;
    // End any take first — the recorder must close held notes at the current
    // beat before [ClipSession.stop] rewinds the transport to the top.
    _record.onTransportStop();
    if (!_editedSession.stop()) return;
    _syncTicker();
  }

  /// Cancel a running count-in and idle its clock, returning whether one was
  /// aborted — a stop or pause during the count. A no-op (returns `false`) when
  /// no count is running.
  bool _abortCountIn() {
    if (!_countIn.isCounting) return false;
    _countIn.cancel();
    _stopCountClock();
    _syncTicker();
    return true;
  }

  // ─── concurrent playback: per-session, group, and all (issue #187) ────────

  /// Start (or **resume**, when paused) the open session at [address],
  /// concurrently with any others already running — each on its own clock and
  /// scene-key band. A no-op (returns `false`) when no session is open for
  /// [address] or it is already playing. Spins the shared frame ticker.
  bool playSession(EntityAddress? address) {
    final session = _sessions[address];
    if (session == null) return false;
    final started = session.isPaused ? session.resume() : session.play();
    if (started) _syncTicker();
    return started;
  }

  /// Pause the open session at [address] (freezing its clock, keeping its
  /// position). A no-op unless it is open and playing. Idles the ticker if
  /// nothing else runs.
  bool pauseSession(EntityAddress? address) {
    final session = _sessions[address];
    if (session == null || !session.pause()) return false;
    _syncTicker();
    return true;
  }

  /// Resume the open session at [address] from a pause. A no-op unless it is
  /// open and paused.
  bool resumeSession(EntityAddress? address) {
    final session = _sessions[address];
    if (session == null || !session.resume()) return false;
    _syncTicker();
    return true;
  }

  /// Stop the open session at [address] (clearing only its own agents). A no-op
  /// unless it is open and playing or paused.
  bool stopSession(EntityAddress? address) {
    final session = _sessions[address];
    if (session == null || !session.stop()) return false;
    _syncTicker();
    return true;
  }

  /// Play (or resume) every open session beneath the group at [group] — the
  /// clips already opened under it start together, each on its own clock (design
  /// §4, `clip.drums` → play all drums). Sessions not yet opened are the panel's
  /// concern (it opens then plays); this acts on the manager's live sessions.
  void playGroup(EntityAddress group) =>
      _forEachInGroup(group, (s) => s.isPaused ? s.resume() : s.play());

  /// Stop every open session beneath the group at [group] (design §4,
  /// `clip.drums` → stop all drums). Each clip clears only its own agents.
  void stopGroup(EntityAddress group) =>
      _forEachInGroup(group, (s) => s.stop());

  /// Stop every session — playing or paused — the panel header's stop-all
  /// (design §4). The scene demo and effect volumes survive; each session clears
  /// only its own agents. Idles the ticker.
  void stopAll() {
    var acted = false;
    for (final session in _sessions.values) {
      if (session.stop()) acted = true;
    }
    if (acted) _syncTicker();
  }

  /// Panic — the MIDI half of the shell-wide stop-everything (issue #264, design
  /// `docs/design/midi-recording.md` §6). In order:
  ///
  /// 1. end any armed take **keeping its notes** (the held notes close at the
  ///    current beat and commit as authored content, exactly as a stop does) —
  ///    done *before* the transports rewind so the close reads the real beat;
  /// 2. abort a running count-in (it started nothing yet);
  /// 3. stop every clip session — playing or paused — each rewinding and clearing
  ///    its own scene agents;
  /// 4. all-notes-off the external MIDI-out port and every materialised voice
  ///    synth — the belt-and-braces silence beyond the per-session stop, reaching
  ///    a held audition note (arm-for-input / test strip) the transport never
  ///    dispatched; and
  /// 5. clear every remaining live scene agent — the whole field, not just the
  ///    playing sessions' bands, so pending spawns despawn.
  ///
  /// Idempotent — every step no-ops when there is nothing to undo, so a
  /// double-panic changes nothing. Effect volumes (placement, not notes) survive.
  void panic() {
    _record.onTransportStop();
    _abortCountIn();
    for (final session in _sessions.values) {
      session.stop();
    }
    _gateway.allNotesOff();
    for (final synth in _voiceSynths.values) {
      synth.allNotesOff();
    }
    _clearAgents();
    _syncTicker();
  }

  /// Apply [action] to every open session whose address is [group] or nests
  /// beneath it, then re-sync the ticker once. A group holds only descendants;
  /// the boot session (`null` address) is never part of a group.
  void _forEachInGroup(EntityAddress group, void Function(ClipSession) action) {
    var matched = false;
    for (final session in _sessions.values) {
      final address = session.address;
      if (address == null) continue;
      if (address == group || address.isDescendantOf(group)) {
        action(session);
        matched = true;
      }
    }
    if (matched) _syncTicker();
  }

  /// Invoked when the **edited** session's loop flag changes (issue #190), so the
  /// owning engine can re-publish the clip document — the loop flag lives in the
  /// payload but isn't carried by the chain / editor / graph the clip publisher
  /// observes. `null` in setups without persistence.
  void Function()? onEditedLoopChanged;

  /// Invoked when the **edited** session changes — a library selection opens a
  /// different clip (issue #197). The owning engine rebinds the clip publisher so
  /// edits to the newly-opened clip persist into *its* entity, moving the
  /// publisher's listeners and bound `clip.` address off the previously edited
  /// session. `null` in setups without persistence.
  void Function()? onEditedSessionChanged;

  /// Whether the edited session loops its declared length (design §4). Toggling
  /// re-pushes the loop length live while playing, without rewriting the notes,
  /// and fires [onEditedLoopChanged] so the change persists.
  bool get loop => _editedSession.loop;
  set loop(bool value) {
    if (_editedSession.loop == value) return;
    _editedSession.loop = value;
    onEditedLoopChanged?.call();
  }

  /// Set the loop flag for the open session at [address] (a library row),
  /// re-pushing live if it is playing. A no-op when no session is open there.
  void setSessionLoop(EntityAddress? address, bool value) {
    _sessions[address]?.loop = value;
  }

  /// Adopt a loaded [document] into the **edited** session's live clip objects in
  /// place (issue #139) — the engine half of restoring a saved clip on project
  /// open. Surfaces bound to the edited session's chain / editor / graph follow
  /// without re-wiring. While playing, the tick's push-on-change picks up the
  /// fresh output within one frame; adoption normally runs on a stopped transport.
  void adoptDocument(ClipDocument document) => _editedSession.adopt(document);

  /// Adopt [document] into the **edited** session in place (issue #139) and
  /// reconcile that session to [address] (issue #197): when it is the boot session
  /// (keyed `null`), re-key it to [address] — with a matching per-clip clock name
  /// — so the panel's later selection of that clip reuses this very session rather
  /// than minting an address-keyed duplicate beside it. This also gives the clip
  /// publisher (which follows the edited session's address) an entity to publish
  /// edits into. A no-op re-key when the session already carries [address]; the
  /// re-key is skipped when a *distinct* session already occupies [address], so a
  /// stale duplicate is never clobbered.
  void adoptDocumentAsEdited(EntityAddress address, ClipDocument document) {
    _editedSession.adopt(document);
    if (_editedSession.address == address) return;
    final existing = _sessions[address];
    if (existing != null && !identical(existing, _editedSession)) return;
    _sessions.remove(_editedSession.address);
    _editedSession.rekey(address: address, clockName: _clockNameFor(address));
    _sessions[address] = _editedSession;
  }

  // ─── shared output mode (microtonal, port, tempo) ────────────────────────

  bool _microtonal;

  /// Whether fractional pitches are voiced as bend (issue #36) — a global output
  /// mode. Flipping it while playing re-pushes the playing sessions so the change
  /// is heard at once.
  @override
  bool get microtonal => _microtonal;
  set microtonal(bool value) {
    if (_microtonal == value) return;
    _microtonal = value;
    for (final s in _sessions.values) {
      if (s.isPlaying) s.pushEvents();
    }
  }

  double _bpm;

  /// Current *session* tempo in beats-per-minute — the clock rate for an
  /// unsubscribed clip. Tempo lives in the transport's domain clock, so updating
  /// it while playing ramps the clock without re-pushing the note list.
  double get bpm => _bpm;
  set bpm(double value) {
    if (value <= 0) return;
    _bpm = value;
    _applyTempoToPlayingSessions();
  }

  @override
  double get sessionBpm => _bpm;

  /// The chosen MIDI output port's **name**, resolved to a device index each time
  /// the port is (re)opened so a replug keeps working (design §5). `null` means
  /// "no explicit choice" — the first available port (index 0) is opened.
  String? _outputPortName;

  /// The chosen MIDI output port's name, or `null` for the default (first port).
  String? get outputPortName => _outputPortName;

  /// Choose the MIDI output port by [name] (design §5). When a port is already
  /// open and no session is playing, the change is applied at once (the open port
  /// is closed and the resolved one opened, or closed when [name] resolves to
  /// nothing); a change while playing takes effect on the next [play]. Setting the
  /// same name is a no-op.
  set outputPortName(String? name) {
    if (_outputPortName == name) return;
    _outputPortName = name;
    if (_anyPlaying || !_gateway.isOpen) return;
    final port = resolveOutputPort();
    if (port != null) {
      _gateway.open(port); // closes the previous port, opens the resolved one
    } else {
      _gateway.close();
    }
  }

  /// The current device index for [_outputPortName], resolved against the live
  /// output-device list (design §5). A `null` name means the first port (index
  /// `0`) when any exists; a name present in no visible port resolves to `null`.
  @override
  int? resolveOutputPort() {
    final name = _outputPortName;
    if (name == null) {
      return _gateway.outputDeviceCount > 0 ? 0 : null;
    }
    for (var i = 0; i < _gateway.outputDeviceCount; i++) {
      if (_gateway.outputDeviceName(i) == name) return i;
    }
    return null;
  }

  /// The tempo-source seam (issue #104) — the list of control-rate sources summed
  /// onto each session's base tempo. Holds a single [FaderTempoSource] today.
  late final TempoSourceStack _tempoSources;

  /// The hand-driven tempo bend — the first source in [_tempoSources] and the
  /// "first gesture" of played tempo. Bipolar, resting at `0`.
  final FaderTempoSource _tempoFader = FaderTempoSource();

  /// The tempo-source seam. Exposed so a future tempo UI can add or inspect
  /// sources; today it carries only [tempoFader].
  @override
  TempoSourceStack get tempoSources => _tempoSources;

  /// The hand fader riding the played domain's tempo (issue #104). Drive its
  /// [FaderTempoSource.position] to bend playback; the playing sessions' clocks
  /// re-ramp on the next change, and because tempo lives in the clock the note
  /// list is never re-pushed.
  FaderTempoSource get tempoFader => _tempoFader;

  /// Re-apply the effective tempo to every playing session's transport clock —
  /// called on a session [bpm] change and whenever the tempo-source stack moves.
  void _applyTempoToPlayingSessions() {
    for (final s in _sessions.values) {
      if (s.isPlaying) s.applyTempo();
    }
  }

  /// The live per-domain tempo overrides a state application laid over the
  /// authored `domain.` tempos (issue #243), keyed by domain name. Performance
  /// state — never persisted, cleared wholesale on a project swap.
  final Map<String, double> _domainTempoOverrides = {};

  @override
  double? domainTempoOverride(String domainName) =>
      _domainTempoOverrides[domainName];

  /// Lay a live tempo override of [bpm] over the domain at [domain] — the
  /// clock-binding half of a state's tempos slice (issue #243). Journal-free:
  /// the authored `domain.` payload is untouched; every playing session
  /// subscribed to the domain re-paces its transport clock at once, and a
  /// later-started session picks the override up through its base-tempo
  /// resolution. A non-positive [bpm] is ignored (clocks cannot run backward).
  void applyDomainTempo(EntityAddress domain, double bpm) {
    if (bpm <= 0) return;
    _domainTempoOverrides[domain.name] = bpm;
    _applyTempoToPlayingSessions();
  }

  /// Drop every live tempo override — a fresh performance runs on authored
  /// tempos. Called by the engine on a project swap.
  void clearDomainTempoOverrides() {
    if (_domainTempoOverrides.isEmpty) return;
    _domainTempoOverrides.clear();
    _applyTempoToPlayingSessions();
  }

  // ─── shared scene field ──────────────────────────────────────────────────

  /// The live scene, keyed by `(channel, pitch)` voice key. Shared across
  /// sessions (one 3D world): a playing session spawns/despawns its agents here,
  /// grabs and effect volumes place into it, and the manager advances it once per
  /// frame ([_stepField]) and pushes the moving set at the sink (issue #79).
  final SceneField _field = SceneField();

  @override
  SceneField get field => _field;

  @override
  MidiGateway get gateway => _gateway;

  @override
  SceneAgentSink? get agentSink => _agentSink;

  @override
  GraphEvalContext liveContext() => GraphEvalContext(
    activeState: _stateMachine?.activeStateAddress,
    variables: _runtimeVariables?.snapshot() ?? const {},
  );

  /// Repoint every open session's live MIDI-graph `state.` guards from
  /// [from] to [to] — the rename-refactor hook the registry-backed state
  /// machine drives (issue #241), so a state rename re-routes guard
  /// evaluation without touching authored notes. The edited session's
  /// registry publisher observes its graph, so the repoint also republishes
  /// the stored clip payload with the rewritten guard. Idempotent — a graph
  /// with no guard on [from] is left untouched.
  void repointStateGuards(EntityAddress from, EntityAddress to) {
    for (final session in _sessions.values) {
      session.graphController.graph.repointGuardState(from, to);
    }
  }

  // ─── voice → channel resolution (design §6) ──────────────────────────────

  /// Maps a note's routed voice to its allocated engine channel at flatten time.
  /// Seeded with just `voice.default` on channel 0 until the racks epic
  /// materialises further voices (issue #205); swap it via [voiceResolver] to
  /// teach the controller the project's live voice → channel table.
  VoiceChannelResolver _voiceResolver;

  /// The live engine synth each internal voice plays, keyed by dotted voice
  /// address — handed in by the engine's rack materialiser (issue #208) so a
  /// session can `connectSynth` its transport to the internal voices its clip
  /// routes to. Empty until the racks are materialised.
  Map<String, MaterialisedSynth> _voiceSynths = const {};

  final Set<String> _unresolvedVoices = <String>{};

  /// The voice → channel table sessions flatten against. Replaceable so the
  /// racks/engine wiring (a later epic issue) can hand in the project's live
  /// allocation without re-plumbing the sessions.
  VoiceChannelResolver get voiceResolver => _voiceResolver;
  set voiceResolver(VoiceChannelResolver resolver) {
    _voiceResolver = resolver;
    for (final s in _sessions.values) {
      if (s.isPlaying) s.pushEvents();
    }
  }

  /// Bind the project's live voice table + synth map into the controller (issue
  /// #208) — the engine's rack materialiser calls this after every re-sync. The
  /// [resolver] carries the internal channel allocation and external channels;
  /// [synths] holds one materialised engine synth per internal voice. Re-pushes
  /// every playing session so its transport re-flattens onto the new channels
  /// **and** reconnects to the new synths / MIDI-out within one audio block.
  void bindVoices(
    VoiceChannelResolver resolver,
    Map<String, MaterialisedSynth> synths,
  ) {
    _voiceResolver = resolver;
    _voiceSynths = synths;
    for (final s in _sessions.values) {
      if (s.isPlaying) s.pushEvents();
    }
  }

  @override
  int? channelForVoice(String? voice) => _voiceResolver.channelFor(voice);

  @override
  MaterialisedSynth? synthForVoice(String? voice) =>
      _voiceSynths[voice ?? _voiceResolver.defaultVoice];

  @override
  bool isExternalVoice(String? voice) => _voiceResolver.externalChannels
      .containsKey(voice ?? _voiceResolver.defaultVoice);

  /// The distinct voices that failed to resolve since the last [clearVoiceIssues]
  /// — an unknown voice a clip routed to played nothing (design §6). Observable
  /// so a surface can tell the performer which voice is missing.
  Set<String> get unresolvedVoices => Set.unmodifiable(_unresolvedVoices);

  @override
  void onUnresolvedVoice(String voice) {
    if (_unresolvedVoices.add(voice)) {
      debugPrint(
        'phi.midi: clip routed to unknown voice "$voice" — its notes are '
        'silent until the voice exists.',
      );
    }
  }

  /// Drop the recorded [unresolvedVoices] — e.g. after the missing voice has
  /// been created, so a stale warning doesn't linger.
  void clearVoiceIssues() => _unresolvedVoices.clear();

  // ─── audition (design §7) ────────────────────────────────────────────────

  /// Parsed MIDI **input** note events off the gateway (design §7) — the stream
  /// the racks voices pane arms a voice against. A passthrough of the gateway
  /// stream so callers depend on the controller, not the bridge directly.
  Stream<MidiInputEvent> get inputEvents => _gateway.inputEvents;

  /// The preview note-off timers still pending, so [dispose] cancels them and a
  /// momentary audition never fires after teardown.
  final List<Timer> _previewTimers = [];

  /// Immediately start [note] on [voice] (design §7) — the **audition** path for
  /// arm-for-input and the on-screen test strip. An internal voice plays its
  /// materialised synth directly; an external voice sends straight to the open
  /// MIDI output on the voice's channel. A no-op for a voice with no live synth
  /// (unmaterialised, past the channel ceiling) and no external channel — it
  /// simply sounds nothing. [voice] `null` is the seeded default; [velocity] is
  /// `0..127`.
  void auditionNoteOn(String? voice, int note, {int velocity = 100}) {
    final synth = synthForVoice(voice);
    if (synth != null) {
      synth.noteOn(note, velocity: (velocity / 127).clamp(0.0, 1.0));
      return;
    }
    if (isExternalVoice(voice)) {
      final channel = channelForVoice(voice);
      if (channel != null) {
        _gateway.sendNoteOn(channel: channel, note: note, velocity: velocity);
      }
    }
  }

  /// Immediately release [note] on [voice] — the note-off half of
  /// [auditionNoteOn].
  void auditionNoteOff(String? voice, int note) {
    final synth = synthForVoice(voice);
    if (synth != null) {
      synth.noteOff(note);
      return;
    }
    if (isExternalVoice(voice)) {
      final channel = channelForVoice(voice);
      if (channel != null) _gateway.sendNoteOff(channel: channel, note: note);
    }
  }

  /// Sound a **momentary** preview of [note] on [voice] — the roll / step-entry
  /// audition (design §7): a note-on now, and a note-off after [hold]. Used when
  /// the performer clicks a note or steps one in with the caret, so the note is
  /// heard through its routed voice without leaving a hung voice.
  void auditionPreview(
    String? voice,
    int note, {
    int velocity = 100,
    Duration hold = const Duration(milliseconds: 350),
  }) {
    auditionNoteOn(voice, note, velocity: velocity);
    late final Timer timer;
    timer = Timer(hold, () {
      _previewTimers.remove(timer);
      auditionNoteOff(voice, note);
    });
    _previewTimers.add(timer);
  }

  /// Scatter the live agents — a one-shot performer action that disperses the
  /// spawned set with a seeded, bounded random impulse and pushes the kicked set
  /// to the sink. A no-op when no agents are alive (or no Scene sink is wired).
  void scatter(Scatter scatter) {
    if (_field.isEmpty) return;
    _field.scatter(scatter);
    _agentSink?.setAgents(_field.agents);
  }

  /// Place an effect volume on the live field (issue #80). Spawned agents inside
  /// it pick up its send on the next tick's [SceneField.step]. Volumes are
  /// placement, not transient motion, so they outlive a transport [stop].
  void addEffectVolume(EffectVolume volume) => _field.addVolume(volume);

  /// Remove a previously placed effect [volume] by identity. Returns `true` if it
  /// was present.
  bool removeEffectVolume(EffectVolume volume) => _field.removeVolume(volume);

  /// Drop every effect volume from the live field.
  void clearEffectVolumes() => _field.clearVolumes();

  /// A snapshot of the effect volumes currently placed, in insertion order.
  List<EffectVolume> get effectVolumes => _field.volumes;

  /// The key of the live agent under [ray], or `null` when it hits none (issue
  /// #82). The Scene surface turns a pointer into a [PickRay] and feeds the result
  /// to [grab].
  int? pick(PickRay ray) => _field.pick(ray);

  /// The current world position of the live agent under [key], or `null` when no
  /// such agent is alive.
  Vector3? agentPosition(int key) => _field.positionOf(key);

  /// Grab the live agent under [key] — begin a direct-manipulation pull. Returns
  /// `true` if an agent was under [key]. Grabbing starts the frame ticker if it
  /// wasn't already spinning, so a grab pull settles even on a stopped Scene.
  bool grab(int key) {
    final grabbed = _field.grab(key);
    if (grabbed) _syncTicker();
    return grabbed;
  }

  /// Move the held grab target the grabbed agent is pulled toward. A no-op when
  /// nothing is grabbed.
  void moveGrabTo(Vector3 target) => _field.moveGrabTo(target);

  /// Release the current grab, handing motion back to the field. Lets the ticker
  /// idle if the release leaves no per-frame work.
  void releaseGrab() {
    _field.release();
    _syncTicker();
  }

  /// Drop every live agent and push the empty set to the sink, so the Scene
  /// clears when the transport stops. Also drops the pick-demo flag.
  void _clearAgents() {
    _sceneDemoLoaded = false;
    if (_field.isEmpty) return;
    _field.clear();
    _agentSink?.setAgents(const []);
  }

  bool _sceneDemoLoaded = false;

  /// Whether the pick-friendly Scene demo (issue #90) is currently loaded.
  bool get isSceneDemoLoaded => _sceneDemoLoaded;

  /// Populate the field with a handful of long-lived, well-separated agents so
  /// the Scene surface's pick / select / grab can be exercised by hand (issue
  /// #90). Reloading replaces the previous demo set.
  void loadSceneDemo() {
    final agents = pickDemoAgents();
    for (var i = 0; i < agents.length; i++) {
      _field.spawn(_sceneDemoKeyBase - i, agents[i]);
    }
    _sceneDemoLoaded = true;
    _agentSink?.setAgents(_field.agents);
  }

  /// Drop the pick-friendly Scene demo, clearing the field and pushing the empty
  /// set to the sink. A no-op when no demo is loaded.
  void clearSceneDemo() {
    if (!_sceneDemoLoaded) return;
    _field.clear();
    _sceneDemoLoaded = false;
    _agentSink?.setAgents(const []);
  }

  /// Base for the pick-demo agents' field keys. Negative, so a demo key never
  /// collides with a playback voice key (`channel * 128 + pitch`, always ≥ 0).
  static const int _sceneDemoKeyBase = -1000;

  // ─── frame ticker ────────────────────────────────────────────────────────

  Timer? _timer;

  bool get _anyPlaying => _sessions.values.any((s) => s.isPlaying);

  /// Run the frame ticker exactly while there is per-frame work — a session is
  /// playing, a count-in is running, or a grab needs realizing on a stopped
  /// Scene — and idle it otherwise. The single frame driver for the shared scene
  /// field in all cases (issue #103).
  void _syncTicker() {
    final needed = _anyPlaying || _field.isGrabbing || _countIn.isCounting;
    if (needed && _timer == null) {
      _timer = Timer.periodic(_tickInterval, _onTick);
    } else if (!needed && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _onTick(Timer _) {
    // Drive a running count-in first: when the clock reaches the downbeat it
    // starts the edited session (and any armed take) this same frame (issue
    // #263), which the session advance below then carries forward.
    _countIn.tick();
    final dtSeconds = _tickInterval.inMicroseconds * 1e-6;
    // Advance every playing session: re-bind its clock (a live domain-chip toggle
    // takes hold here), re-push on change, cross its Scene window, move its
    // playhead. For the single edited clip this is exactly one session.
    for (final session in _sessions.values) {
      if (!session.isPlaying) continue;
      session.applyTempo();
      session.advance(dtSeconds);
    }
    // Fire a recording pass boundary when the edited transport crosses the loop
    // end (issue #261) — after advancing, so it reads the latest beat.
    _record.tick();
    // Advance the shared field once per frame — playing or not, so drift and grab
    // pulls integrate on the one ticker.
    _stepField(dtSeconds);
    // A despawn may have ended a grab (or stop cleared the field): re-check
    // whether the ticker still has work.
    _syncTicker();
  }

  /// Advance the live agents by [dtSeconds] and push the moved set to the sink,
  /// so spawned agents visibly drift (and grab pulls settle) each frame. No-op
  /// when the field is empty.
  void _stepField(double dtSeconds) {
    if (_field.isEmpty) return;
    _field.step(dtSeconds);
    _agentSink?.setAgents(_field.agents);
  }

  /// Release the ticker, every session (each disposes its transport, playhead,
  /// graph, editor and chain), the shared field, the output port and the tempo
  /// seam. Call when the owning engine stops.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _record.dispose();
    _countIn.dispose();
    _countClock?.dispose();
    _countClock = null;
    for (final timer in _previewTimers) {
      timer.cancel();
    }
    _previewTimers.clear();
    final wasPlaying = _anyPlaying;
    for (final session in _sessions.values) {
      session.dispose();
    }
    if (wasPlaying) _gateway.allNotesOff();
    _clearAgents();
    _gateway.close();
    _tempoSources.removeListener(_applyTempoToPlayingSessions);
    _tempoSources.dispose();
    _tempoFader.dispose();
  }
}
