import 'package:flutter_test/flutter_test.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';
import 'gui_value_protocol_contract.dart';

/// [FakePatcherGateway]'s GUI value protocol (issue #469): the same contract
/// the real engine passes, plus what the fake records for assertions.
void main() {
  guiValueProtocolContract(FakePatcherGateway.new);

  group('recording', () {
    late FakePatcherGateway gateway;
    late int inst;

    setUp(() {
      gateway = FakePatcherGateway();
      inst = gateway.createInstance();
    });

    test('lists and messages are logged per inlet', () {
      final pack = gateway.createObject(inst, Obj.gRslider);
      gateway
        ..sendList(inst, pack, 1, '0.4')
        ..sendMessage(inst, pack, 0, 'set 0 0.2');

      expect(gateway.calls, contains('sendList:$pack:1:0.4'));
      expect(gateway.calls, contains('sendMessage:$pack:0:set 0 0.2'));
      expect(gateway.nodes[pack]!.listsByInlet, {
        1: ['0.4'],
        0: ['set 0 0.2'],
      });
      expect(gateway.nodes[pack]!.guiCells, ['0.2', '0']);
    });

    test('writes travel as lists on inlet 0, as yse sends them', () {
      final range = gateway.createObject(inst, Obj.gRslider);
      gateway
        ..setGuiValueAt(inst, range, 1, '0.8')
        ..restoreGuiValue(inst, range, '0.1 0.9');

      expect(
        gateway.calls,
        containsAllInOrder(<String>[
          'sendList:$range:0:set 1 0.8',
          'sendList:$range:0:0.1 0.9',
        ]),
      );
    });

    test('an unmodelled selector is recorded and leaves the state alone', () {
      final stepper = gateway.createObject(inst, Obj.gIncdec);
      gateway.nodes[stepper]!.guiValue = '3';

      gateway.sendMessage(inst, stepper, 0, 'inc');

      expect(gateway.nodes[stepper]!.listsByInlet[0], ['inc']);
      expect(gateway.guiValue(inst, stepper), '3');
    });

    test('a refused write is not sent at all', () {
      final bang = gateway.createObject(inst, Obj.gButton);
      gateway.restoreGuiValue(inst, bang, '1');
      expect(gateway.calls.where((c) => c.startsWith('sendList')), isEmpty);
    });
  });
}
