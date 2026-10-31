import '../../domain/project/entity_address.dart';

/// The insert-effect chain as the live-coding **control plane** sees it — the
/// receiving end of `phi.ctl.fx.*` parameter sets (design
/// `docs/design/live-coding.md` §4, issue #316).
///
/// `fx.reverb.mix = 0.25` — equivalently `fx.reverb.set("mix", 0.25)` — in a
/// script publishes `phi.ctl.fx.reverb.mix` carrying the value; the
/// [ControlPlaneDispatcher] decodes the [fx] entity address, the trailing
/// [param] name, and the numeric [value], then calls [setParam]. The owning
/// controller (an adapter over the live fx registry — an `fx.` entity's
/// `FxDefinition` param bag) applies it through the normal path, so a
/// script-set knob is indistinguishable from a panel-set one.
///
/// Effect params are numeric: continuous knobs and discrete counts alike ride
/// as doubles (an `FxDefinition` holds `name → double`), and the controller
/// rounds where a param is integral. A non-numeric frame never reaches here —
/// it degrades to a dispatcher notice instead.
///
/// A port, not the controller itself, so the dispatcher is testable against a
/// fake. The production adapter is `LiveFxControlPort` (issue #348), which
/// writes the value onto the live effect handle without journaling.
abstract interface class FxControlPort {
  /// Set the [param] of the effect instance at [fx] to [value] (the decoded
  /// numeric bus value).
  void setParam(EntityAddress fx, String param, double value);
}
