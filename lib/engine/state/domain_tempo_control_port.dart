import '../../domain/project/entity_address.dart';
import '../bridge/tempo_control_port.dart';

/// The live tempo stack as the control plane's [TempoControlPort] — the
/// receiving end of `phi.ctl.domain.<name>.tempo` (design
/// `docs/design/live-coding.md` §4, issue #233; production wiring #334).
///
/// A script `domain.drum.tempo = 124` publishes `phi.ctl.domain.drum.tempo`
/// carrying the BPM; the [ControlPlaneDispatcher] decodes it and calls
/// [setTempo]. This forwards to [_apply] — the engine's live domain-tempo
/// override, the *same* seam a fired state's tempos slice applies through
/// (issue #243): the playing sessions subscribed to the domain re-pace their
/// clocks at once and a running metronome click bound to it re-paces too, all
/// journal-free (the authored `domain.` payload is untouched).
///
/// Closure-backed so the engine composes the exact override it already runs the
/// state-slice application through, rather than duplicating that wiring here.
class DomainTempoControlPort implements TempoControlPort {
  const DomainTempoControlPort(this._apply);

  final void Function(EntityAddress domain, double bpm) _apply;

  @override
  void setTempo(EntityAddress domain, double bpm) => _apply(domain, bpm);
}
