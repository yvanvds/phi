import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

import 'gui_value_protocol_contract.dart';

/// The GUI value protocol (issue #469) through [RealPatcherGateway] and the
/// real engine — headless, like `real_patcher_gateway_engine_test.dart`. The
/// shared contract pins the fake to the same answers; the selector test is
/// engine-only because the fake does not model object-specific selectors.
void main() {
  var engineUp = false;

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
  });

  tearDownAll(() {
    if (engineUp) System.instance.close();
  });

  guiValueProtocolContract(RealPatcherGateway.new);

  test('sendMessage dispatches a selector (.incdec inc / dec)', () {
    final gateway = RealPatcherGateway();
    addTearDown(gateway.disposeAll);
    final inst = gateway.createInstance();
    final stepper = gateway.createObject(inst, Obj.gIncdec);

    gateway
      ..sendMessage(inst, stepper, 0, 'inc')
      ..sendMessage(inst, stepper, 0, 'inc')
      ..sendMessage(inst, stepper, 0, 'inc')
      ..sendMessage(inst, stepper, 0, 'dec');

    expect(gateway.guiValue(inst, stepper), '2');
  });
}
