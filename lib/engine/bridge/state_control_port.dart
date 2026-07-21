import '../../domain/project/entity_address.dart';

/// The state machine as the live-coding **control plane** sees it — the
/// receiving end of `phi.ctl.state.fire` commands (design
/// `docs/design/live-coding.md` §4, issue #233).
///
/// `state.fire("break")` publishes `phi.ctl.state.fire` carrying the target
/// name; `state.<machine>.fire("break")` addresses a named machine. The
/// [ControlPlaneDispatcher] decodes it and calls [fire] with [machine] (`null`
/// for the root `state.fire`, i.e. the default/only machine) and the [target]
/// state name. The owning controller resolves [target] to a transition and
/// fires it through the normal path.
///
/// A port so the dispatcher is testable against a fake; the real wiring adapts
/// the live `StateMachineController`.
abstract interface class StateControlPort {
  /// Fire toward the state named [target] on [machine] — or, when [machine] is
  /// `null`, on the default state machine (the bare `state.fire(...)`).
  void fire(EntityAddress? machine, String target);
}
