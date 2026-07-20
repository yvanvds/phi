import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/project/entity_address.dart';
import '../bridge/midi_input_event.dart';
import 'engine_midi_controller.dart';

/// Drives **arming a voice for MIDI-in** and **on-screen test-strip audition**
/// for the racks voices pane (design `docs/design/racks-and-voices.md` §7,
/// issue #211).
///
/// A [ChangeNotifier] the pane binds to. It holds the single **armed** voice
/// (one at a time — arming another disarms the first), subscribes to the
/// gateway's parsed MIDI-in stream through [EngineMidiController.inputEvents],
/// and plays the armed voice **immediately** on every incoming note (direct
/// note-on / note-off, never through a transport). The pane's one-octave test
/// strip does the same from the mouse via [pressKey] / [releaseKey].
///
/// Held notes are tracked with the voice they started sounding on, so disarming
/// (or switching the armed voice) releases exactly what it started — no hung
/// voice when the performer re-arms mid-hold. It owns only its arm state + the
/// input subscription; the actual sounding goes through the shared
/// [EngineMidiController] audition path, so internal and external voices are
/// handled there.
class VoiceAuditionController extends ChangeNotifier {
  VoiceAuditionController({required EngineMidiController midi}) : _midi = midi {
    _sub = midi.inputEvents.listen(_onInput);
  }

  final EngineMidiController _midi;
  StreamSubscription<MidiInputEvent>? _sub;

  EntityAddress? _armed;

  /// Notes currently sounding, keyed by MIDI note number → the voice address
  /// that started them, so a note-off releases the same voice even after the arm
  /// moved.
  final Map<int, String> _held = {};

  /// The voice armed for MIDI-in + test-strip audition, or `null` when none is.
  EntityAddress? get armed => _armed;

  /// Whether [voice] is the currently armed voice.
  bool isArmed(EntityAddress voice) => _armed == voice;

  /// Arm [voice] if it isn't, or disarm it if it is — the row's arm toggle. The
  /// single-arm invariant holds: arming a second voice disarms the first, and
  /// any notes it was holding are released first so nothing hangs.
  void toggleArm(EntityAddress voice) {
    if (_armed == voice) {
      disarm();
    } else {
      arm(voice);
    }
  }

  /// Arm [voice] for input, releasing everything the previously armed voice was
  /// holding. A no-op when it is already armed.
  void arm(EntityAddress voice) {
    if (_armed == voice) return;
    _releaseAll();
    _armed = voice;
    notifyListeners();
  }

  /// Disarm — MIDI-in and the test strip fall silent. Releases any held notes.
  void disarm() {
    if (_armed == null) return;
    _releaseAll();
    _armed = null;
    notifyListeners();
  }

  /// Press a test-strip key: sound [note] on the armed voice (design §7). A
  /// no-op when no voice is armed. [velocity] is `0..127`.
  void pressKey(int note, {int velocity = 100}) {
    final armed = _armed;
    if (armed == null) return;
    _startNote(armed.format(), note, velocity);
  }

  /// Release a test-strip key: stop [note] on whatever voice sounded it.
  void releaseKey(int note) => _stopNote(note);

  void _onInput(MidiInputEvent event) {
    final armed = _armed;
    if (armed == null) return;
    // Arm overrides routing: any incoming note plays the armed voice, regardless
    // of the message's own channel.
    if (event.type == MidiInputEventType.noteOn) {
      _startNote(armed.format(), event.note, event.velocity);
    } else {
      _stopNote(event.note);
    }
  }

  void _startNote(String voice, int note, int velocity) {
    // Re-press of a held note: release the old sounding first so it can't leak.
    final previous = _held[note];
    if (previous != null) _midi.auditionNoteOff(previous, note);
    _held[note] = voice;
    _midi.auditionNoteOn(voice, note, velocity: velocity);
  }

  void _stopNote(int note) {
    final voice = _held.remove(note);
    if (voice != null) _midi.auditionNoteOff(voice, note);
  }

  void _releaseAll() {
    for (final entry in _held.entries) {
      _midi.auditionNoteOff(entry.value, entry.key);
    }
    _held.clear();
  }

  @override
  void dispose() {
    _releaseAll();
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
