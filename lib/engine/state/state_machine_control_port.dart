import '../../domain/project/entity_address.dart';
import '../bridge/state_control_port.dart';
import 'state_trigger_scheduler.dart';

/// The live state machine as the control plane's [StateControlPort] — the
/// receiving end of `phi.ctl.state.fire` (design `docs/design/live-coding.md`
/// §4, issue #233; behaviour landed with issue #244).
///
/// Delegates to [StateTriggerScheduler.fireTo], which resolves the live
/// state's outbound transition toward the named target and fires it through
/// the normal path — the code-trigger seam of design `state-graph.md` §5. v1
/// has exactly one state machine, so the optional [machine] qualifier is
/// accepted and ignored; a named-machine dispatch lands with a later epic.
class StateMachineControlPort implements StateControlPort {
  const StateMachineControlPort(this._scheduler);

  final StateTriggerScheduler _scheduler;

  @override
  void fire(EntityAddress? machine, String target) => _scheduler.fireTo(target);
}
