import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/midi/edit/clip_edit_command.dart';
import '../../domain/midi/edit/composite_clip_command.dart';
import '../../domain/midi/edit/set_length_command.dart';
import '../../domain/midi/midi_clip.dart';
import '../../domain/midi/record/take_recorder.dart';
import '../bridge/midi_input_event.dart';
import 'record_target.dart';

/// Record arm + capture flow for the MIDI editor (issue #261, design
/// `docs/design/midi-recording.md` §3).
///
/// A [ChangeNotifier] the transport row's record-arm button binds to. It holds
/// the **record-arm** flag (performance state, never persisted) and turns the
/// live MIDI-in stream into a clip's source notes by driving a [TakeRecorder]
/// against the edited session ([RecordTarget]):
///
/// - **arm + play** starts a take; **arming while playing** punches in live;
///   **stop or disarm** ends the take (its notes are kept — they are authored
///   content, exactly like drawn notes).
/// - **Overdub per loop pass** (§8 decision 2): with auto-extend *off* the loop
///   wraps and every pass commits as one undo step through the target's
///   [RecordTarget.undoScope], so Ctrl+Z peels passes newest-first.
/// - **Auto-extend interplay** (§3): with auto-extend *on*, playing past the end
///   grows the clip (one continuous pass, the length grow journaled *with* the
///   notes so a single undo restores both); *off*, the loop wraps and overdubs.
/// - Recorded notes carry the **armed voice** (§8 decision 3) read from the
///   racks audition path — the same voice you monitor while playing.
///
/// The recorder mutates nothing itself: each finished pass is a [ClipEditCommand]
/// this controller runs through the undo scope, so the ordinary revision bump
/// refreshes the ghost / re-pushes playback live within one block.
class RecordController extends ChangeNotifier {
  RecordController({
    required Stream<MidiInputEvent> input,
    required this._target,
    this._armedVoice,
  }) {
    _sub = input.listen(_onInput);
  }

  /// Resolves the session a take should capture into — the edited session in the
  /// engine, a fake in tests. Read at take start and held for the take's life.
  final RecordTarget? Function() _target;

  /// Reads the racks audition path's armed voice as a dotted address, or `null`
  /// for an unrouted take (design §3: monitoring *is* that path, and recorded
  /// notes carry the armed voice). Settable so the shell wires it once both
  /// controllers exist.
  String? Function()? _armedVoice;
  set armedVoice(String? Function()? reader) => _armedVoice = reader;

  StreamSubscription<MidiInputEvent>? _sub;

  bool _armed = false;

  /// Whether record is armed — the transport row's record button lights on this.
  /// Arm state is performance state; it is never persisted (§3).
  bool get armed => _armed;

  /// Whether a take is currently being captured.
  bool get isRecording => _recorder?.isRecording ?? false;

  TakeRecorder? _recorder;

  /// The target captured at take start; held so the clock, wrap boundary and
  /// commit path all read the same session across the take.
  RecordTarget? _take;

  /// Whether this take **grows** the clip (auto-extend on) rather than wrapping
  /// the loop and overdubbing (off). Captured at take start.
  bool _grow = false;

  /// The last loop index seen in overdub mode, so a boundary crossing fires
  /// exactly one [TakeRecorder.wrap] per lap (and punch-in mid-loop doesn't fire
  /// a burst of stale wraps).
  int _lastLoop = 0;

  /// The furthest note-end beat this take reaches — the grow-to-fit target in
  /// auto-extend mode.
  double _maxEnd = 0;

  // ── arm ────────────────────────────────────────────────────────────────────

  /// Toggle record-arm — the transport row's record button. Arming while the
  /// edited transport is already playing punches in at once; disarming mid-take
  /// ends the take (keeping its notes).
  void toggleArm() => _armed ? disarm() : arm();

  /// Arm record. When the edited transport is already running this punches in —
  /// a take starts immediately (§3). A no-op when already armed.
  void arm() {
    if (_armed) return;
    _armed = true;
    final t = _target();
    if (t != null && t.isPlaying) _startTake(t);
    notifyListeners();
  }

  /// Disarm record, ending any take in progress (its notes are kept). A no-op
  /// when not armed.
  void disarm() {
    if (!_armed) return;
    _armed = false;
    if (isRecording) _endTake();
    notifyListeners();
  }

  // ── engine transport hooks ──────────────────────────────────────────────────

  /// The edited transport started (or resumed): begin a take when armed and not
  /// already recording. Called by the engine on play/resume.
  void onTransportPlay() {
    if (!_armed || isRecording) return;
    final t = _target();
    if (t == null) return;
    _startTake(t);
    notifyListeners();
  }

  /// The edited transport stopped (or paused): end any take in progress. Called
  /// by the engine on stop/pause — *before* it resets the transport, so the
  /// held-note close reads the real stop beat.
  void onTransportStop() {
    if (!isRecording) return;
    _endTake();
    notifyListeners();
  }

  /// One frame of the engine's ticker: in overdub mode, fire a pass boundary
  /// each time the play-relative beat crosses the clip's declared length. Grow
  /// mode never wraps — it extends the clip at commit instead.
  void tick() {
    final r = _recorder;
    final t = _take;
    if (r == null || t == null || _grow) return;
    final total = t.clip.totalBeats;
    if (total <= 0) return;
    final loop = (t.recordBeat / total).floor();
    while (_lastLoop < loop) {
      r.wrap();
      _lastLoop++;
    }
  }

  // ── internals ───────────────────────────────────────────────────────────────

  void _startTake(RecordTarget t) {
    _take = t;
    _grow = t.autoExtend;
    _maxEnd = 0;
    final total = t.clip.totalBeats;
    // Anchor the wrap counter to the current lap so a punch-in mid-loop doesn't
    // immediately fire wraps for laps already elapsed before the take.
    _lastLoop = (!_grow && total > 0) ? (t.recordBeat / total).floor() : 0;
    _recorder = TakeRecorder(
      clip: t.clip,
      clock: _clock,
      commit: _commit,
      clipAddress: t.address,
      voice: _armedVoice?.call(),
    );
    _recorder!.start();
  }

  void _endTake() {
    final r = _recorder;
    final t = _take;
    if (r == null || t == null) return;
    // A note still held at stop closes at the stop beat; count it toward the
    // grow-to-fit extent before the recorder commits the final pass.
    if (_grow && r.hasHeldNotes) _maxEnd = math.max(_maxEnd, _clock());
    r.stop();
    _recorder = null;
    _take = null;
  }

  /// The clip-relative beat the recorder stamps from. Grow mode reads the raw
  /// play-relative beat (notes land past the end, the clip grows to fit); overdub
  /// mode folds it into the loop window so each lap restarts at `0`.
  double _clock() {
    final t = _take;
    if (t == null) return 0;
    final beat = t.recordBeat;
    if (_grow) return beat;
    final total = t.clip.totalBeats;
    return total > 0 ? beat % total : beat;
  }

  void _onInput(MidiInputEvent e) {
    final r = _recorder;
    if (r == null) return;
    if (e.type == MidiInputEventType.noteOn) {
      // Re-read the armed voice per note so a re-arm mid-take tags subsequent
      // notes with the new voice (§8 decision 3); a held note keeps its own.
      r.voice = _armedVoice?.call();
      r.noteOn(e.note, e.velocity);
    } else {
      _maxEnd = math.max(_maxEnd, _clock());
      r.noteOff(e.note);
    }
  }

  void _commit(ClipEditCommand batch) {
    final t = _take;
    if (t == null) return;
    var command = batch;
    if (_grow) {
      final clip = t.clip;
      final grown = _barsToFit(_maxEnd, clip);
      if (grown > clip.bars) {
        // Journal the length grow *with* the pass — one undo restores both,
        // exactly as a drawn note overrunning the end auto-extends (issue #190).
        command = CompositeClipCommand(clip, [
          SetLengthCommand(
            clip,
            bars: grown,
            beatsPerBar: clip.beatsPerBar,
            clipAddress: t.address,
          ),
          batch,
        ], clipAddress: t.address);
      }
    }
    t.undoScope.run(command);
  }

  /// The bar count needed to contain a note ending at [endBeat] (rounded up to a
  /// whole bar), never below the clip's current [MidiClip.bars].
  static int _barsToFit(double endBeat, MidiClip clip) {
    final beatsPerBar = clip.beatsPerBar;
    if (beatsPerBar <= 0) return clip.bars;
    final needed = (endBeat / beatsPerBar - 1e-9).ceil();
    return needed > clip.bars ? needed : clip.bars;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
