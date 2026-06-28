import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../bridge/midi_gateway.dart';

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
/// source, so toggling a transform changes what is heard on the next play.
class EngineMidiController {
  EngineMidiController({
    required MidiTransformChain chain,
    required MidiGateway gateway,
    ClipEditor? editor,
    double bpm = 120,
    int outputPort = 0,
    Duration tickInterval = const Duration(milliseconds: 16),
  }) : _chain = chain,
       _gateway = gateway,
       editor = editor ?? ClipEditor(chain.source),
       _bpm = bpm,
       _outputPort = outputPort,
       _tickInterval = tickInterval;

  final MidiTransformChain _chain;
  final MidiGateway _gateway;
  final int _outputPort;
  final Duration _tickInterval;

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

  /// Snapshot of the transformed notes taken at [play]. Playback is
  /// deterministic for the duration of a run; edits apply on the next play.
  List<MidiNote> _scheduled = const [];

  /// Notes currently sounding, by `(channel, pitch)` — so the player can
  /// release exactly what it pressed if a transform overlaps voices.
  final Set<int> _sounding = <int>{};

  /// Start (or restart) playback from the top of the clip. Opens the output
  /// port lazily on first play. No-op if already playing.
  void play() {
    if (_playing) return;
    if (!_gateway.isOpen && _gateway.outputDeviceCount > _outputPort) {
      _gateway.open(_outputPort);
    }
    _scheduled = _chain.output;
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
    _absBeat = 0;
    _prevAbsBeat = 0;
    _playhead.value = 0;
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
  void _dispatchWindow(double from, double to) {
    final total = _chain.source.totalBeats;
    if (total <= 0 || _scheduled.isEmpty) return;

    final firstLoop = (from / total).floor();
    final lastLoop = (to / total).floor();
    for (var loop = firstLoop; loop <= lastLoop; loop++) {
      final base = loop * total;
      for (final note in _scheduled) {
        final onAt = base + note.start;
        if (onAt >= from && onAt < to) _noteOn(note);
        final offAt = base + note.start + note.duration;
        if (offAt >= from && offAt < to) _noteOff(note);
      }
    }
  }

  void _noteOn(MidiNote note) {
    final velocity = (note.velocity * 127).round().clamp(1, 127);
    _gateway.noteOn(
      channel: note.channel,
      pitch: note.pitch,
      velocity: velocity,
    );
    _sounding.add(_voiceKey(note.channel, note.pitch));
  }

  void _noteOff(MidiNote note) {
    final key = _voiceKey(note.channel, note.pitch);
    if (!_sounding.remove(key)) return;
    _gateway.noteOff(channel: note.channel, pitch: note.pitch);
  }

  int _voiceKey(int channel, int pitch) => channel * 128 + pitch;

  /// Release timers, notifiers, the shared editor, the chain, and the output
  /// port. Call when the owning engine stops.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_playing) {
      _gateway.allNotesOff();
      _playing = false;
    }
    _gateway.close();
    _playhead.dispose();
    editor.dispose();
    _chain.dispose();
  }
}
