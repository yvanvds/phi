import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Counts which read form the controller uses, so a test can hold it to the
/// engine's one-read-form-per-object-per-frame rule (issue #469).
class _ReadSpyGateway extends FakePatcherGateway {
  int wholeReads = 0;
  final List<int> cellReads = [];

  @override
  String guiValue(int instanceId, int handleId) {
    wholeReads++;
    return super.guiValue(instanceId, handleId);
  }

  @override
  String guiValueAt(int instanceId, int handleId, int index) {
    cellReads.add(index);
    return super.guiValueAt(instanceId, handleId, index);
  }
}

/// The controller side of the GUI value protocol (issue #469): per-cell
/// polling for [GuiValueRead.cells] bodies, the cell window, and the
/// multi-cell / list / selector wrappers the new control bodies build on.
void main() {
  late _ReadSpyGateway gateway;
  late PatcherController controller;

  NodeDescriptor desc(String type, {String args = '', GuiValueRead? read}) =>
      NodeDescriptor(
        type: type,
        defaultSize: const Size(120, 80),
        defaultArgs: args,
        inputs: const [],
        outputs: const [],
        buildBody: (ctx, node, controller) => const SizedBox.shrink(),
        readsGuiValue: true,
        guiValueRead: read ?? GuiValueRead.whole,
      );

  PatchNode add(String type, {String args = '', GuiValueRead? read}) {
    final d = desc(type, args: args, read: read);
    NodeTypeRegistry.instance.register(d);
    return controller.addNode(desc: d, position: Offset.zero);
  }

  FakeNode native(PatchNode node) => gateway.nodes[node.id.value]!;

  setUp(() {
    gateway = _ReadSpyGateway();
    controller = PatcherController(gateway);
    NodeTypeRegistry.instance.clear();
  });

  tearDown(() {
    controller.dispose();
    NodeTypeRegistry.instance.clear();
  });

  group('per-cell polling', () {
    test('a cells body is polled per cell and never read whole', () {
      final bank = add(Obj.gMultislider, args: '4', read: GuiValueRead.cells);
      native(bank).guiCells = ['1', '2', '3', '4'];

      controller.refreshGuiValues();
      expect(controller.guiValueCellsOf(bank.id), ['1', '2', '3', '4']);
      expect(controller.guiValueCountOf(bank.id), 4);
      expect(controller.guiValueCellOf(bank.id, 2), '3');
      expect(controller.guiValueCellOf(bank.id, 9), '');
      // guiValueOf answers from the same cells, as guiValue spells them.
      expect(controller.guiValueOf(bank.id), '1 2 3 4');

      expect(gateway.wholeReads, 0, reason: 'one read form per object');
      expect(gateway.cellReads, [0, 1, 2, 3], reason: 'the poll read once');
    });

    test('a whole body is still read whole and never per cell', () {
      final slider = add(Obj.gSlider);
      native(slider).guiValue = '0.5';

      controller.refreshGuiValues();

      expect(gateway.wholeReads, 1);
      expect(gateway.cellReads, isEmpty);
    });

    test('a cable-driven cell wakes the node once, an idle one never', () {
      final range = add(Obj.gRslider, read: GuiValueRead.cells);
      var woken = 0;
      range.addListener(() => woken++);

      expect(controller.refreshGuiValues(), 1, reason: 'first read');
      expect(controller.refreshGuiValues(), 0);
      expect(controller.refreshGuiValues(), 0);

      native(range).guiCells = ['0', '0.7'];
      expect(controller.refreshGuiValues(), 1);
      expect(controller.refreshGuiValues(), 0);
      expect(woken, 2);
      expect(controller.guiValueCellOf(range.id, 1), '0.7');
    });

    test('a bank-size change alone wakes the node', () {
      final bank = add(Obj.gMultislider, args: '2', read: GuiValueRead.cells);
      controller.refreshGuiValues();

      native(bank).guiCells = ['0', '0', '0'];
      expect(controller.refreshGuiValues(), 1);
      expect(controller.guiValueCountOf(bank.id), 3);
    });

    test('a cell window reads only the cells it repaints', () {
      final keys = add(Obj.gKslider, read: GuiValueRead.cells);
      controller.refreshGuiValues();
      gateway.cellReads.clear();

      controller.setGuiCellWindow(keys.id, start: 60, end: 72);
      native(keys).guiCells = [...native(keys).guiCells]
        ..[64] = '100'
        ..[10] = '90';
      expect(controller.refreshGuiValues(), 1);

      expect(gateway.cellReads, List.generate(12, (i) => 60 + i));
      expect(controller.guiValueCellOf(keys.id, 64), '100');
      expect(
        controller.guiValueCellOf(keys.id, 10),
        '0',
        reason: 'outside the window: the last value read',
      );
      expect(controller.guiValueCountOf(keys.id), 128);

      // A window past a bank that shrank is clamped, not an error.
      controller.setGuiCellWindow(keys.id, start: 120, end: 200);
      native(keys).guiCells = List.filled(4, '0');
      controller.refreshGuiValues();
      expect(controller.guiValueCountOf(keys.id), 4);

      controller.setGuiCellWindow(keys.id);
      native(keys).guiCells = ['1', '2', '3', '4'];
      controller.refreshGuiValues();
      expect(controller.guiValueCellsOf(keys.id), ['1', '2', '3', '4']);
    });

    test('the cell cache goes with a deleted node', () {
      final range = add(Obj.gRslider, read: GuiValueRead.cells);
      controller.refreshGuiValues();
      controller.removeNode(range.id);
      expect(controller.guiValueCellsOf(range.id), isEmpty);
      expect(controller.refreshGuiValues(), 0);
    });
  });

  group('writes', () {
    test('setGuiValueCell writes one cell and the next read shows it', () {
      final range = add(Obj.gRslider, read: GuiValueRead.cells);
      controller.refreshGuiValues();

      expect(controller.setGuiValueCell(range.id, 1, '0.8'), isTrue);
      expect(gateway.calls.last, 'sendList:${range.id.value}:0:set 1 0.8');
      expect(controller.guiValueCellOf(range.id, 1), '0.8');
      expect(controller.setGuiValueCell(range.id, 2, '0.8'), isFalse);
    });

    test('restoreGuiValueOf puts the whole state back', () {
      final range = add(Obj.gRslider, read: GuiValueRead.cells);
      expect(controller.guiValueIsSettableOf(range.id), isTrue);
      expect(controller.restoreGuiValueOf(range.id, '0.2 0.6'), isTrue);
      expect(controller.guiValueCellsOf(range.id), ['0.2', '0.6']);
    });

    test('an unsettable node refuses both writes', () {
      final bang = add(Obj.gButton);
      expect(controller.guiValueIsSettableOf(bang.id), isFalse);
      expect(controller.restoreGuiValueOf(bang.id, '1'), isFalse);
      expect(controller.setGuiValueCell(bang.id, 0, '1'), isFalse);
    });

    test('setControlList and sendControlMessage reach the inlet', () {
      final bank = add(Obj.gMultislider, args: '2', read: GuiValueRead.cells);
      controller.refreshGuiValues();

      controller.setControlList(bank.id, inlet: 0, list: '0.1 0.2 0.3');
      expect(controller.guiValueCountOf(bank.id), 3);

      controller.sendControlMessage(bank.id, inlet: 0, message: 'fetch 1');
      expect(gateway.calls.last, 'sendMessage:${bank.id.value}:0:fetch 1');
    });

    test('a scalar push outdates the cell cache too', () {
      final bank = add(Obj.gMultislider, args: '2', read: GuiValueRead.cells);
      controller.refreshGuiValues();
      controller.setControlValue(bank.id, inlet: 0, value: 0.5);
      expect(controller.guiValueCellsOf(bank.id), ['0.5']);
    });
  });

  // Issue #514: the poll's read is the only one in a frame, so the body it
  // wakes sees the value that woke it, even when that read was destructive.
  group('whole-read cache', () {
    test('a woken momentary .led sees the press its poll consumed', () {
      final led = add(Obj.gLed, args: 'momentary');
      controller.refreshGuiValues();
      final seen = <String>[];
      led.addListener(() => seen.add(controller.guiValueOf(led.id)));
      final idle = gateway.wholeReads;

      // A press over a cable: the engine holds it until the next read.
      gateway.sendInt(controller.instanceId, led.id.value, 0, 1);

      expect(controller.refreshGuiValues(), 1);
      expect(seen, ['1'], reason: 'the body sees the press');
      expect(gateway.wholeReads, idle + 1, reason: 'one read per frame');
      expect(controller.refreshGuiValues(), 1, reason: 'cleared next frame');
      expect(seen, ['1', '0']);
    });

    test('guiValueOf answers from the poll until a write outdates it', () {
      final slider = add(Obj.gSlider);
      native(slider).guiValue = '0.5';
      controller.refreshGuiValues();
      final reads = gateway.wholeReads;

      expect(controller.guiValueOf(slider.id), '0.5');
      expect(gateway.wholeReads, reads, reason: 'from the poll');

      controller.setControlValue(slider.id, inlet: 0, value: 0.25);
      expect(controller.guiValueOf(slider.id), '0.25', reason: 're-read');
      expect(controller.guiValueOf(slider.id), '0.25');
      expect(gateway.wholeReads, reads + 1, reason: 'then remembered');
      expect(controller.refreshGuiValues(), 0, reason: 'already shown');
    });

    test('a node never polled is read once, then answered from memory', () {
      final dial = add(Obj.gDial);
      native(dial).guiValue = '0.3';
      expect(controller.guiValueOf(dial.id), '0.3');
      expect(controller.guiValueOf(dial.id), '0.3');
      expect(gateway.wholeReads, 1);
    });

    test('new params outdate the remembered value', () {
      final text = add(Obj.gTextedit, args: 'hello');
      expect(controller.guiValueOf(text.id), 'hello');
      native(text).guiValue = 'bye';
      controller.setNodeParams(text.id, 'bye');
      expect(controller.guiValueOf(text.id), 'bye');
    });
  });
}
