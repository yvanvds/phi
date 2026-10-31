import '../../domain/project/entity_address.dart';
import '../bridge/fx_control_port.dart';

/// The live insert-effect handles as the control plane's [FxControlPort] — the
/// receiving end of `phi.ctl.fx.<addr>.<param>` (design
/// `docs/design/live-coding.md` §4, issue #348).
///
/// A script `fx.reverb.impact = 0.25` publishes `phi.ctl.fx.reverb.impact`
/// carrying the value; the [ControlPlaneDispatcher] decodes it and calls
/// [setParam]. This forwards to [_apply] — the engine's live fx-param setter,
/// which writes the value onto the materialised effect through the same
/// click-free setter a definition edit uses, **without journaling** (a
/// performance gesture, mirroring how a fired state's mix slice applies bus
/// levels live). The authored `fx.` payload is untouched.
///
/// Closure-backed so the engine composes the exact live seam it owns (the rack
/// materialiser exists only while the engine runs) rather than this port
/// holding a materialiser that a stop → start replaces.
class LiveFxControlPort implements FxControlPort {
  const LiveFxControlPort(this._apply);

  final void Function(EntityAddress fx, String param, double value) _apply;

  @override
  void setParam(EntityAddress fx, String param, double value) =>
      _apply(fx, param, value);
}
