import '../../domain/project/entity_address.dart';

/// The tempo stack as the live-coding **control plane** sees it — the receiving
/// end of `phi.ctl.domain.<name>.tempo` commands (design
/// `docs/design/live-coding.md` §4, issue #233).
///
/// `domain.drum.tempo = 124` publishes `phi.ctl.domain.drum.tempo` carrying the
/// BPM; the [ControlPlaneDispatcher] decodes it and calls [setTempo] with the
/// [domain] entity address and the target [bpm]. The owning controller (the
/// time-domain tempo-source stack) applies it through the normal path.
///
/// A port so the dispatcher is testable against a fake; the real wiring adapts
/// the live time-domain registry.
abstract interface class TempoControlPort {
  /// Set the base tempo of the time domain at [domain] to [bpm].
  void setTempo(EntityAddress domain, double bpm);
}
