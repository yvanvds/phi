import '../../domain/project/entity_address.dart';
import '../bridge/voice_control_port.dart';
import 'engine_midi_controller.dart';

/// The racks **audition** path as the control plane's [VoiceControlPort] — the
/// receiving end of `phi.ctl.voice.<name>.note` / `.off` (design
/// `docs/design/live-coding.md` §4, §7, issue #233; production wiring #334).
///
/// A script `voice.bells.note(60)` publishes `phi.ctl.voice.bells.note`; the
/// [ControlPlaneDispatcher] decodes the pitch/velocity and calls [note], which
/// sounds the voice **immediately** through [EngineMidiController.auditionNoteOn]
/// (an internal voice on its materialised synth, an external voice straight to
/// the open MIDI-out) — exactly the path the racks pane's arm-for-input and
/// on-screen test strip use, so a code-sounded note is indistinguishable from a
/// hand-played one.
///
/// The audition path is stateless, so this port tracks the notes it started
/// (per voice) to honour `voice.bells.off()` — a bare off with no pitch releases
/// **every** note the voice is holding, matching the DSL verb. `voice.bells.off(60)`
/// releases just that pitch. Everything no-ops gracefully when no MIDI subsystem
/// is wired (`_midi == null`).
class AuditionVoiceControlPort implements VoiceControlPort {
  AuditionVoiceControlPort(this._midi);

  final EngineMidiController? _midi;

  /// The pitches currently sounding per dotted voice address, so a bare
  /// `off()` can release exactly what this port started.
  final Map<String, Set<int>> _held = {};

  @override
  void note(EntityAddress voice, {required int pitch, int velocity = 100}) {
    final midi = _midi;
    if (midi == null) return;
    final key = voice.format();
    midi.auditionNoteOn(key, pitch, velocity: velocity);
    (_held[key] ??= <int>{}).add(pitch);
  }

  @override
  void off(EntityAddress voice, {int? pitch}) {
    final midi = _midi;
    if (midi == null) return;
    final key = voice.format();
    if (pitch != null) {
      midi.auditionNoteOff(key, pitch);
      final held = _held[key];
      if (held != null) {
        held.remove(pitch);
        if (held.isEmpty) _held.remove(key);
      }
      return;
    }
    final held = _held.remove(key);
    if (held == null) return;
    for (final n in held) {
      midi.auditionNoteOff(key, n);
    }
  }
}
