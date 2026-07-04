import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/graph/graph_eval_context.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/transforms/agent_spawn_transform.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/scene/effect_volume.dart';
import '../../domain/scene/pick_ray.dart';
import '../../domain/scene/scatter.dart';
import '../../domain/scene/scene_agent.dart';
import '../../domain/scene/scene_demo.dart';
import '../../domain/scene/scene_field.dart';
import '../../domain/state_machine/state_graph.dart';
import '../bridge/midi_gateway.dart';
import '../bridge/scene_agent_sink.dart';
import 'midi_graph_controller.dart';

/// Engine-side player for the MIDI surface.
///
/// Owns the [MidiTransformChain] (source clip → transforms → [output]) and
/// its [ClipEditor], so the player and the piano-roll editor share one source
/// clip — edits land in the same place the player reads from. Drives a
/// looping playhead off a periodic timer; as the playhead crosses each note
/// boundary it forwards `noteOn` / `noteOff` to the injected [MidiGateway].
///
/// Per Phi's vision (§3.7) clips are "interpreted, not played": the player
/// reads the **transformed** notes, not the raw source, live each tick — so
/// editing a note or toggling a transform while the clip loops is heard
/// immediately, the representation and the MIDI output being one thing, not two
/// copies.
///
/// Which transformed notes depends on the clip's [MidiGraphController.mode]
/// (issue #77): a **chain** clip reads the linear [MidiTransformChain.output]
/// (the zero-overhead default); a **graph** clip reads the branching
/// [MidiTransformGraph]'s `evaluate` against a live [GraphEvalContext] mirroring
/// [StateGraph.activeStateId], so a state-guarded branch actually re-routes the
/// sounding notes as the live state flips.
class EngineMidiController {
  EngineMidiController({
    required MidiTransformChain chain,
    required MidiGateway gateway,
    ClipEditor? editor,
    SceneAgentSink? agentSink,
    StateGraph? stateGraph,
    RuntimeVariableRegistry? runtimeVariables,
    double bpm = 120,
    int outputPort = 0,
    this.microtonal = false,
    Duration tickInterval = const Duration(milliseconds: 16),
  }) : _chain = chain,
       _gateway = gateway,
       _agentSink = agentSink,
       _stateGraph = stateGraph,
       _runtimeVariables = runtimeVariables,
       editor = editor ?? ClipEditor(chain.source),
       graphController = MidiGraphController.seededFrom(chain),
       _bpm = bpm,
       _outputPort = outputPort,
       _tickInterval = tickInterval;

  final MidiTransformChain _chain;
  final MidiGateway _gateway;

  /// The live state machine, mirrored into the graph's [GraphEvalContext] so a
  /// `state · break` edge opens exactly while that state is live. `null` in
  /// setups without a state machine — the graph then evaluates against the
  /// empty context (only unconditional edges fire).
  final StateGraph? _stateGraph;

  /// The live runtime-variable registry, mirrored into the graph's
  /// [GraphEvalContext] so a `var · mode = lead` edge opens exactly while that
  /// variable holds that value (issue #78). `null` in setups without a registry
  /// — the graph then sees no variables (a `var = x` guard stays closed).
  final RuntimeVariableRegistry? _runtimeVariables;

  /// The branching transform-graph editor (issue #65), seeded from [chain] so
  /// it opens on the working linear chain. Shares [chain]'s source clip, so
  /// piano-roll edits flow into its `evaluate`. Its [MidiGraphController.mode]
  /// decides whether playback reads the linear chain or this graph (issue #77);
  /// the MIDI surface binds both its node-and-cable canvas *and* that mode to
  /// this instance, so what the performer sees and what they hear stay in step.
  final MidiGraphController graphController;

  /// Optional Scene sink. When wired and the chain carries an active
  /// [AgentSpawnTransform], each note-on spawns a live `SceneAgent` and its
  /// note-off despawns it (issue #37). `null` in setups without a Scene.
  final SceneAgentSink? _agentSink;
  final int _outputPort;
  final Duration _tickInterval;

  /// Opt-in microtonal output (issue #36). When `true`, a note's fractional
  /// pitch is split into its nearest semitone (sent as the Note-On pitch) and
  /// the leftover cents, voiced as a per-channel pitch-bend emitted just before
  /// the Note-On. When `false` the fractional pitch is simply rounded to the
  /// nearest semitone — the pre-microtonal behaviour, so nothing bends unless
  /// asked. Toggleable live; takes effect on the next note dispatched.
  ///
  /// Assumes the synth's pitch-bend range is the General-MIDI default of ±2
  /// semitones. Bend is per-channel, so simultaneous notes with *different*
  /// detunes must be routed to different channels to bend independently.
  bool microtonal;

  /// The shared authoring controller. Gestures on the piano roll edit the
  /// same clip this player reads.
  final ClipEditor editor;

  /// The transform chain this player reads. Exposed so the surface can bind
  /// its chip panel and ghost layer to the same instance.
  MidiTransformChain get chain => _chain;

  double _bpm;

  /// Current playback tempo in beats-per-minute. Updating it while playing
  /// takes effect on the next tick — the playhead keeps its position.
  double get bpm => _bpm;
  set bpm(double value) => _bpm = value <= 0 ? _bpm : value;

  final ValueNotifier<double> _playhead = ValueNotifier<double>(0);

  /// Position of the playhead within the clip, in beats `[0, totalBeats)`.
  /// `0` while stopped. The piano-roll painter binds to this.
  ValueListenable<double> get playhead => _playhead;

  bool _playing = false;

  /// Whether the transport is currently running.
  bool get isPlaying => _playing;

  Timer? _timer;

  /// Absolute beats elapsed since [play], across loop boundaries. The
  /// scheduling window each tick is `[_prevAbsBeat, _absBeat)`.
  double _absBeat = 0;
  double _prevAbsBeat = 0;

  /// Notes currently sounding, by `(channel, pitch)` — so the player can
  /// release exactly what it pressed if a transform overlaps voices.
  final Set<int> _sounding = <int>{};

  /// The live scene, keyed by the same `(channel, pitch)` voice key as
  /// [_sounding], so a note-off despawns exactly the agent its note-on
  /// spawned. Only populated when an [SceneAgentSink] is wired *and* the chain
  /// carries an active [AgentSpawnTransform]. The player advances it each tick
  /// ([_field.step]) and pushes the moving set at the sink, so spawned agents
  /// are live participants that drift rather than static points (issue #79).
  final SceneField _field = SceneField();

  /// Start (or restart) playback from the top of the clip. Opens the output
  /// port lazily on first play. No-op if already playing.
  void play() {
    if (_playing) return;
    if (!_gateway.isOpen && _gateway.outputDeviceCount > _outputPort) {
      _gateway.open(_outputPort);
    }
    _absBeat = 0;
    _prevAbsBeat = 0;
    _playhead.value = 0;
    _playing = true;
    _timer = Timer.periodic(_tickInterval, _onTick);
  }

  /// Stop playback, silence any sounding notes, and rewind the playhead.
  void stop() {
    if (!_playing) return;
    _timer?.cancel();
    _timer = null;
    _playing = false;
    _gateway.allNotesOff();
    _sounding.clear();
    _clearAgents();
    _absBeat = 0;
    _prevAbsBeat = 0;
    _playhead.value = 0;
  }

  /// Scatter the live agents — a one-shot performer action that disperses the
  /// spawned set with a seeded, bounded random impulse and pushes the kicked
  /// set to the sink so the throw is seen at once. Deterministic: the same
  /// [scatter] over the same live set always produces the same dispersal.
  ///
  /// A no-op when no agents are alive (or no Scene sink is wired), so
  /// triggering scatter over an empty field never touches the sink.
  void scatter(Scatter scatter) {
    if (_field.isEmpty) return;
    _field.scatter(scatter);
    _agentSink?.setAgents(_field.agents);
  }

  /// Place an effect volume on the live field (issue #80). Spawned agents that
  /// sit inside it pick up its send on the next tick's [SceneField.step] —
  /// surfaced on each agent's [SceneAgent.sends] — and drop it again when they
  /// drift or are dragged out. This is the seam that lets the spawn→scene path
  /// actually route agents through effect volumes; without a volume placed here
  /// the machinery is dormant.
  ///
  /// Volumes are placement, not transient motion, so they outlive a transport
  /// [stop] (which clears agents but leaves volumes standing) — place them once,
  /// then play. Not pushed to the sink here: a volume changes nothing until an
  /// agent is stepped through it, and the next [step] recomputes membership.
  void addEffectVolume(EffectVolume volume) => _field.addVolume(volume);

  /// Remove a previously placed effect [volume] by identity. Returns `true` if
  /// it was present. Agents keep whatever sends the last [step] assigned until
  /// the next [step] recomputes them against the reduced set.
  bool removeEffectVolume(EffectVolume volume) => _field.removeVolume(volume);

  /// Drop every effect volume from the live field. Agents' sends clear on the
  /// next [step].
  void clearEffectVolumes() => _field.clearVolumes();

  /// A snapshot of the effect volumes currently placed on the live field, in
  /// insertion order. Detached from internal state.
  List<EffectVolume> get effectVolumes => _field.volumes;

  /// The key of the live agent under [ray], or `null` when it hits none — the
  /// pick half of direct manipulation (issue #82). The Scene surface turns a
  /// pointer into a [PickRay] and feeds the result to [grab]; code can build a
  /// ray and pick without a viewport, so anything the mouse can do, code can
  /// too.
  int? pick(PickRay ray) => _field.pick(ray);

  /// The current world position of the live agent under [key], or `null` when
  /// no such agent is alive. The Scene surface reads this to anchor a pointer
  /// drag at the grabbed agent's depth and to keep the selection highlight on
  /// the moving agent as the field advances.
  Vector3? agentPosition(int key) => _field.positionOf(key);

  /// Grab the live agent under [key] — begin a direct-manipulation pull. While
  /// held the field draws the agent toward the target set by [moveGrabTo] on
  /// each playback tick's [SceneField.step]; [releaseGrab] hands motion back
  /// with the velocity the pull built up (a moving grab throws, a settled one
  /// doesn't). Returns `true` if an agent was under [key]. The pull is realized
  /// by the field's step — driven here by the running transport; the Scene
  /// surface will drive its own step once it graduates.
  bool grab(int key) => _field.grab(key);

  /// Move the held grab target the grabbed agent is pulled toward. A no-op when
  /// nothing is grabbed.
  void moveGrabTo(Vector3 target) => _field.moveGrabTo(target);

  /// Release the current grab, handing motion back to the field. A no-op when
  /// nothing is grabbed.
  void releaseGrab() => _field.release();

  /// Advance the field from the Scene surface's own ticker, so a grab pull is
  /// realized even when the transport isn't running. A no-op while playing —
  /// the playback tick ([_stepAgents]) already steps the field, and a second
  /// step per frame would move every agent twice as fast — and when the field
  /// is empty. Pushes the moved set to the sink so the drag is seen at once.
  void stepFromSurface(double dtSeconds) {
    if (_playing || _field.isEmpty) return;
    _field.step(dtSeconds);
    _agentSink?.setAgents(_field.agents);
  }

  /// Drop every live agent and push the empty set to the sink, so the Scene
  /// clears when the transport stops. No-op when nothing is spawned. Also drops
  /// the pick-demo flag, since a cleared field holds no demo agents either.
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
  /// the Scene surface's pick / select / grab can be exercised by hand without
  /// waiting on the short, clustered agents playback spawns (issue #90).
  ///
  /// A dev aid, meant for the idle (stopped) Scene: the agents are keyed off a
  /// negative base so they never collide with a playback voice key, sit still
  /// (zero velocity), and stay until [clearSceneDemo] or a transport stop drops
  /// them. Reloading replaces the previous demo set. Pushes the set to the sink
  /// so the agents appear at once.
  void loadSceneDemo() {
    final agents = pickDemoAgents();
    for (var i = 0; i < agents.length; i++) {
      _field.spawn(_sceneDemoKeyBase - i, agents[i]);
    }
    _sceneDemoLoaded = true;
    _agentSink?.setAgents(_field.agents);
  }

  /// Drop the pick-friendly Scene demo, clearing the field and pushing the
  /// empty set to the sink. A no-op when no demo is loaded.
  void clearSceneDemo() {
    if (!_sceneDemoLoaded) return;
    _field.clear();
    _sceneDemoLoaded = false;
    _agentSink?.setAgents(const []);
  }

  /// Base for the pick-demo agents' field keys. Negative, so a demo key never
  /// collides with a playback voice key (`channel * 128 + pitch`, always ≥ 0).
  static const int _sceneDemoKeyBase = -1000;

  void _onTick(Timer _) {
    final dtSeconds = _tickInterval.inMicroseconds * 1e-6;
    final dBeats = dtSeconds * (_bpm / 60.0);
    _prevAbsBeat = _absBeat;
    _absBeat += dBeats;
    _dispatchWindow(_prevAbsBeat, _absBeat);
    _stepAgents(dtSeconds);

    final total = _chain.source.totalBeats;
    _playhead.value = total > 0 ? _absBeat % total : _absBeat;
  }

  /// Advance the live agents by [dtSeconds] and push the moved set to the sink,
  /// so spawned agents visibly drift each frame. No-op when the field is empty,
  /// which keeps a Scene-less setup (or an inactive spawn chip) from ever
  /// touching the sink.
  void _stepAgents(double dtSeconds) {
    if (_field.isEmpty) return;
    _field.step(dtSeconds);
    _agentSink?.setAgents(_field.agents);
  }

  /// The transformed notes playback reads this tick, chosen by the clip's
  /// [MidiGraphController.mode]: the linear [MidiTransformChain.output] for a
  /// chain clip, or the branching graph's `evaluate` against the live context
  /// for a graph clip. Both are memoised, so reading every tick is an O(1) hit
  /// between edits (and, for the graph, between state flips).
  List<MidiNote> get _playbackNotes =>
      graphController.mode == MidiClipMode.graph
      ? graphController.graph.evaluate(_liveContext)
      : _chain.output;

  /// The live evaluation context — the state machine's `activeStateId` and the
  /// runtime registry's current values mirrored in, exactly as the graph
  /// preview does — so playback and preview agree on which branches are open.
  GraphEvalContext get _liveContext => GraphEvalContext(
    activeStateId: _stateGraph?.activeStateId,
    variables: _runtimeVariables?.snapshot() ?? const {},
  );

  /// Fire every note event whose absolute beat falls in `[from, to)`. Note
  /// events repeat every `totalBeats` (the clip loops), so the same source
  /// event is mapped into each loop iteration the window spans.
  ///
  /// Reads the clip's transformed notes ([_playbackNotes]) *live* each tick, so
  /// editing the clip, toggling a transform, or flipping the live state while
  /// it loops is heard on the next window — the played notes and the authored
  /// clip are one and the same.
  void _dispatchWindow(double from, double to) {
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
    final velocity = (note.velocity * 127).round().clamp(1, 127);
    final semitone = _semitoneOf(note);
    if (microtonal) {
      _gateway.pitchBend(
        channel: note.channel,
        value: _bendFor(note, semitone),
      );
    }
    _gateway.noteOn(channel: note.channel, pitch: semitone, velocity: velocity);
    _sounding.add(_voiceKey(note.channel, semitone));
    _spawnAgent(note, semitone);
  }

  void _noteOff(MidiNote note) {
    final semitone = _semitoneOf(note);
    final key = _voiceKey(note.channel, semitone);
    if (!_sounding.remove(key)) return;
    _gateway.noteOff(channel: note.channel, pitch: semitone);
    _despawnAgent(key);
  }

  /// Spawn a live scene agent for [note] when a Scene sink is wired and an
  /// active [AgentSpawnTransform] is in the chain. The agent lives until the
  /// matching note-off ([_despawnAgent]).
  void _spawnAgent(MidiNote note, int semitone) {
    final sink = _agentSink;
    if (sink == null) return;
    final transform = _activeSpawnTransform;
    if (transform == null) return;
    final spawn = transform.spawnFor(note);
    _field.spawn(
      _voiceKey(note.channel, semitone),
      SceneAgent(
        position: spawn.position,
        velocity: spawn.velocity,
        voiceIndex: spawn.voiceIndex,
      ),
    );
    sink.setAgents(_field.agents);
  }

  /// Despawn the agent a note-on left under [key], if any, and push the
  /// updated set to the sink.
  void _despawnAgent(int key) {
    if (!_field.despawn(key)) return;
    _agentSink?.setAgents(_field.agents);
  }

  /// The first active [AgentSpawnTransform] in the chain, or `null` if none —
  /// so toggling the spawn chip off (or removing it) stops driving the Scene.
  AgentSpawnTransform? get _activeSpawnTransform {
    for (final t in _chain.transforms) {
      if (t is AgentSpawnTransform && t.active) return t;
    }
    return null;
  }

  /// The integer MIDI pitch a note is voiced on — the semitone it rounds to.
  int _semitoneOf(MidiNote note) => note.pitch.round().clamp(0, 127);

  /// 14-bit pitch-bend that voices [note]'s leftover cents (its distance from
  /// [semitone]). Centred at 8192, scaled by the assumed ±2-semitone range.
  int _bendFor(MidiNote note, int semitone) {
    final cents = (note.pitch - semitone) * 100.0;
    final bend = _bendCenter + (cents / _bendRangeCents) * _bendCenter;
    return bend.round().clamp(0, 16383);
  }

  int _voiceKey(int channel, int pitch) => channel * 128 + pitch;

  static const int _bendCenter = 8192;
  static const double _bendRangeCents = 200.0; // GM default: ±2 semitones.

  /// Release timers, notifiers, the shared editor, the chain, and the output
  /// port. Call when the owning engine stops.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_playing) {
      _gateway.allNotesOff();
      _playing = false;
    }
    _clearAgents();
    _gateway.close();
    _playhead.dispose();
    graphController.dispose();
    editor.dispose();
    _chain.dispose();
  }
}
