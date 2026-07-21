import '../../domain/project/entity_address.dart';

/// The voice controller as the live-coding **control plane** sees it — the
/// receiving end of `phi.ctl.voice.*` commands, the immediate audition path
/// (design `docs/design/live-coding.md` §4, issue #233).
///
/// The [ControlPlaneDispatcher] decodes a tapped `phi.ctl.voice.<name>.note` /
/// `.off` frame into one of these calls; the owning controller (voices, epic
/// #203) sounds [voice] through the normal audition path. In v1 this rides the
/// host-mediated plane (one-to-two-tick latency, fine for note audition); a
/// later engine `synth.` prefix upgrades it to engine-direct transparently,
/// without the `phi` verb — or this port — changing (design §4, §8).
///
/// A port, not the controller itself: the dispatcher lands with a fake here so
/// the control plane is testable before epic #203 merges; the real wiring
/// activates as that epic lands.
abstract interface class VoiceControlPort {
  /// Sound [pitch] (MIDI note) on [voice] at [velocity] (`0..127`, default
  /// `100`) — `voice.bells.note(60)` / `voice.bells.note(60, 40)`.
  void note(EntityAddress voice, {required int pitch, int velocity = 100});

  /// Release a note on [voice]: a specific [pitch] (`voice.bells.off(60)`), or —
  /// when [pitch] is `null` — every note the voice is holding
  /// (`voice.bells.off()`).
  void off(EntityAddress voice, {int? pitch});
}
