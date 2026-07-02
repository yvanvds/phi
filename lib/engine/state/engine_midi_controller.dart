import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/transforms/agent_spawn_transform.dart';
import '../../domain/scene/scene_agent.dart';
import '../bridge/midi_gateway.dart';
import '../bridge/scene_agent_sink.dart';

/// Engine-side player for the MIDI surface.
///
/// Owns the [MidiTransformChain] (source clip → transforms → [output]) and
/// its [ClipEditor], so the player and the piano-roll editor share one source
/// clip — edits land in the same place the player reads from. Drives a
/// looping playhead off a periodic timer; as the playhead crosses each note
/// boundary it forwards `noteOn` / `noteOff` to the injected [MidiGateway].
///
/// Per Phi's vision (§3.7) clips are "interpreted, not played": the player
/// reads the chain's **transformed** [MidiTransformChain.output], not the raw
/// source. Output is read live each tick, so editing a note or toggling a
/// transform while the clip loops is heard immediately — the representation
/// and the MIDI output are one thing, not two copies.
class EngineMidiController {
  EngineMidiController({
    required MidiTransformChain chain,
    required MidiGateway gateway,
    ClipEditor? editor,
    SceneAgentSink? agentSink,
    double bpm = 120,
    int outputPort = 0,
    this.microtonal = false,
    Duration tickInterval = const Duration(milliseconds: 16),
  }) : _chain = chain,
       _gateway = gateway,
       _agentSink = agentSink,
       editor = editor ?? ClipEditor(chain.source),
       _bpm = bpm,
       _outputPort = outputPort,
       _tickInterval = tickInterval;

  final MidiTransformChain _chain;
  final MidiGateway _gateway;

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

  /// Live scene agents, keyed by the same `(channel, pitch)` voice key as
  /// [_sounding], so a note-off despawns exactly the agent its note-on
  /// spawned. Only populated when an [SceneAgentSink] is wired *and* the chain
  /// carries an active [AgentSpawnTransform].
  final Map<int, SceneAgent> _agents = <int, SceneAgent>{};

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

  /// Drop every live agent and push the empty set to the sink, so the Scene
  /// clears when the transport stops. No-op when nothing is spawned.
  void _clearAgents() {
    if (_agents.isEmpty) return;
    _agents.clear();
    _agentSink?.setAgents(const []);
  }

  void _onTick(Timer _) {
    final dBeats = _tickInterval.inMicroseconds * 1e-6 * (_bpm / 60.0);
    _prevAbsBeat = _absBeat;
    _absBeat += dBeats;
    _dispatchWindow(_prevAbsBeat, _absBeat);

    final total = _chain.source.totalBeats;
    _playhead.value = total > 0 ? _absBeat % total : _absBeat;
  }

  /// Fire every note event whose absolute beat falls in `[from, to)`. Note
  /// events repeat every `totalBeats` (the clip loops), so the same source
  /// event is mapped into each loop iteration the window spans.
  ///
  /// Reads the chain's transformed [MidiTransformChain.output] *live* each
  /// tick, so editing the clip or toggling a transform while it loops is
  /// heard on the next window — the played notes and the edited clip are one
  /// and the same.
  void _dispatchWindow(double from, double to) {
    final total = _chain.source.totalBeats;
    final notes = _chain.output;
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
    _agents[_voiceKey(note.channel, semitone)] = SceneAgent(
      position: spawn.position,
      voiceIndex: spawn.voiceIndex,
    );
    sink.setAgents(_agents.values.toList(growable: false));
  }

  /// Despawn the agent a note-on left under [key], if any, and push the
  /// updated set to the sink.
  void _despawnAgent(int key) {
    if (_agents.remove(key) == null) return;
    _agentSink?.setAgents(_agents.values.toList(growable: false));
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
    editor.dispose();
    _chain.dispose();
  }
}
