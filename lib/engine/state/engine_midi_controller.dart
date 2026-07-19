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
import '../../domain/state_machine/state_graph.dart';
import '../../domain/time_domains/fader_tempo_source.dart';
import '../../domain/time_domains/tempo_source_stack.dart';
import '../bridge/midi_gateway.dart';
import '../bridge/scene_agent_sink.dart';
import 'clip_session.dart';
import 'clip_session_host.dart';
import 'midi_graph_controller.dart';

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
    required MidiGateway gateway,
    ClipEditor? editor,
    SceneAgentSink? agentSink,
    StateGraph? stateGraph,
    RuntimeVariableRegistry? runtimeVariables,
    double bpm = 120,
    String? outputPortName,
    bool microtonal = false,
    Duration tickInterval = const Duration(milliseconds: 16),
  }) : _gateway = gateway,
       _agentSink = agentSink,
       _stateGraph = stateGraph,
       _runtimeVariables = runtimeVariables,
       _microtonal = microtonal,
       _bpm = bpm,
       _outputPortName = outputPortName,
       _tickInterval = tickInterval {
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
  }

  final MidiGateway _gateway;

  /// Optional Scene sink. When wired and a playing session's chain carries an
  /// active spawn transform, each note-on spawns a live agent (issue #37). `null`
  /// in setups without a Scene.
  final SceneAgentSink? _agentSink;

  /// The live state machine, mirrored into the graph's [GraphEvalContext] so a
  /// `state · break` edge opens exactly while that state is live. `null` in setups
  /// without a state machine — the graph then evaluates against the empty context.
  final StateGraph? _stateGraph;

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
  /// (`channel * 128 + pitch` maxes at `15 * 128 + 127 = 2047`), so the bands
  /// never overlap.
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

  /// Open the clip entity at [address] as the edited session (design §3, §4):
  /// its session becomes the one the editor binds to. Reuses an already-open
  /// session for [address] (never re-adopting over live edits); otherwise creates
  /// one from [document] — source + linear chain, plus the branching graph and
  /// mode when the document carries them.
  ///
  /// This is the library-selection seam the panel UI (a later issue) drives; the
  /// running single-clip app still swaps clip *contents* through [adoptDocument]
  /// in place, so nothing calls this yet in production.
  ClipSession openSession(EntityAddress address, ClipDocument document) {
    final existing = _sessions[address];
    if (existing != null) {
      _editedSession = existing;
      return existing;
    }
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
    _sessions[address] = session;
    _editedSession = session;
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
  void play() {
    _editedSession.play();
    _syncTicker();
  }

  /// Pause the edited session — halt its dispatch (`allNotesOff` so no voice
  /// hangs) and freeze its clock, keeping the beat position so [resume]
  /// continues mid-loop. Idles the ticker if nothing else needs it. No-op unless
  /// playing.
  void pause() {
    if (!_editedSession.pause()) return;
    _syncTicker();
  }

  /// Resume the edited session from a [pause], then spin the frame ticker. No-op
  /// unless paused.
  void resume() {
    if (!_editedSession.resume()) return;
    _syncTicker();
  }

  /// Stop the edited session's playback (clearing its own scene agents) and idle
  /// the ticker if nothing else needs it. No-op if already stopped. Concurrent
  /// clips and the scene demo are untouched — stopping a clip clears only its
  /// own agents (design §4).
  void stop() {
    if (!_editedSession.stop()) return;
    _syncTicker();
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

  /// Whether the edited session loops its declared length (design §4). Toggling
  /// re-pushes the loop length live while playing, without rewriting the notes.
  bool get loop => _editedSession.loop;
  set loop(bool value) => _editedSession.loop = value;

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
    activeStateId: _stateGraph?.activeStateId,
    variables: _runtimeVariables?.snapshot() ?? const {},
  );

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
  /// playing, or a grab needs realizing on a stopped Scene — and idle it
  /// otherwise. The single frame driver for the shared scene field in all cases
  /// (issue #103).
  void _syncTicker() {
    final needed = _anyPlaying || _field.isGrabbing;
    if (needed && _timer == null) {
      _timer = Timer.periodic(_tickInterval, _onTick);
    } else if (!needed && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _onTick(Timer _) {
    final dtSeconds = _tickInterval.inMicroseconds * 1e-6;
    // Advance every playing session: re-bind its clock (a live domain-chip toggle
    // takes hold here), re-push on change, cross its Scene window, move its
    // playhead. For the single edited clip this is exactly one session.
    for (final session in _sessions.values) {
      if (!session.isPlaying) continue;
      session.applyTempo();
      session.advance(dtSeconds);
    }
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
