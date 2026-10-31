import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/state/live_fx_control_port.dart';

/// The real `fx` leg of the control plane (issue #348): a decoded
/// `phi.ctl.fx.<addr>.<param>` set forwards to the engine's live fx-param seam.
void main() {
  test(
    'setParam forwards the fx address, param and value to the apply seam',
    () {
      final applied = <(EntityAddress, String, double)>[];
      final port = LiveFxControlPort(
        (fx, param, value) => applied.add((fx, param, value)),
      );

      port.setParam(EntityAddress.parse('fx.reverb'), 'impact', 0.25);
      port.setParam(EntityAddress.parse('fx.verbs.hall'), 'frequency', 800);

      expect(applied, [
        (EntityAddress.parse('fx.reverb'), 'impact', 0.25),
        (EntityAddress.parse('fx.verbs.hall'), 'frequency', 800.0),
      ]);
    },
  );
}
