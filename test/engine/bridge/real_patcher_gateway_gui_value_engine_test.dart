import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

import 'gui_value_protocol_contract.dart';

/// The GUI value protocol (issue #469) through [RealPatcherGateway] and the
/// real engine — headless, like `real_patcher_gateway_engine_test.dart`. The
/// shared contract pins the fake to the same answers, `.incdec`'s `inc` / `dec`
/// selectors included (issue #470).
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

  guiValueProtocolContract(
    RealPatcherGateway.new,
    // The wrapper reads the native value twice (a length query, then the
    // fill), so the press is consumed before Dart sees it.
    pressReadSkip: 'yvanvds/dart-yse#106: the wrapper consumes the press',
  );
}
