import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patcher_gateway.dart';
import 'package:yse/yse.dart';

/// The GUI value protocol contract (issue #469), run against **both**
/// gateways: `real_patcher_gateway_gui_value_engine_test.dart` drives it
/// through the real engine and `fake_patcher_gateway_gui_value_test.dart`
/// through [FakePatcherGateway], so the fake the controller and widget tests
/// lean on cannot drift from libYSE.
///
/// Values are compared as numbers: the engine spells a float `0.25` or `0.`,
/// the fake `0.25` or `0`, and no caller depends on the spelling.
void guiValueProtocolContract(PatcherGateway Function() makeGateway) {
  late PatcherGateway gateway;
  late int inst;

  setUp(() {
    gateway = makeGateway();
    inst = gateway.createInstance();
  });

  tearDown(() => gateway.disposeAll());

  List<num?> numbers(Iterable<String> cells) => [
    for (final c in cells) num.tryParse(c),
  ];

  List<String> cellsOf(int handle) => [
    for (var i = 0; i < gateway.guiValueCount(inst, handle); i++)
      gateway.guiValueAt(inst, handle, i),
  ];

  test('a scalar control has one cell, equal to its whole value', () {
    final slider = gateway.createObject(inst, Obj.gSlider);
    gateway.sendFloat(inst, slider, 0, 0.5);

    expect(gateway.guiValueCount(inst, slider), 1);
    expect(gateway.guiValueAt(inst, slider, 0), gateway.guiValue(inst, slider));
    expect(num.parse(gateway.guiValueAt(inst, slider, 0)), 0.5);
    expect(gateway.guiValueAt(inst, slider, 1), '', reason: 'past the end');
    expect(gateway.guiValueAt(inst, slider, -1), '', reason: 'negative');
    expect(gateway.guiValueIsSettable(inst, slider), isTrue);
  });

  test('an .rslider round-trips one cell through setGuiValueAt', () {
    final range = gateway.createObject(inst, Obj.gRslider);
    expect(gateway.guiValueCount(inst, range), 2);
    expect(gateway.guiValueIsSettable(inst, range), isTrue);

    expect(gateway.setGuiValueAt(inst, range, 1, '0.75'), isTrue);
    expect(gateway.setGuiValueAt(inst, range, 0, '0.25'), isTrue);

    expect(num.parse(gateway.guiValueAt(inst, range, 0)), 0.25);
    expect(num.parse(gateway.guiValueAt(inst, range, 1)), 0.75);
    expect(numbers(gateway.guiValue(inst, range).split(' ')), [0.25, 0.75]);
  });

  test('a cell write past the count is refused and sends nothing', () {
    final range = gateway.createObject(inst, Obj.gRslider);
    gateway.restoreGuiValue(inst, range, '0.1 0.9');

    expect(gateway.setGuiValueAt(inst, range, 2, '0.5'), isFalse);
    expect(gateway.setGuiValueAt(inst, range, -1, '0.5'), isFalse);
    expect(numbers(cellsOf(range)), [0.1, 0.9]);
  });

  test('restoreGuiValue puts a whole multi-cell state back', () {
    final range = gateway.createObject(inst, Obj.gRslider);
    expect(gateway.restoreGuiValue(inst, range, '0.1 0.9'), isTrue);
    expect(numbers(cellsOf(range)), [0.1, 0.9]);

    // Read whole, restore whole: the documented round trip.
    final saved = gateway.guiValue(inst, range);
    gateway.setGuiValueAt(inst, range, 0, '0.5');
    gateway.restoreGuiValue(inst, range, saved);
    expect(numbers(cellsOf(range)), [0.1, 0.9]);
  });

  test('a list resizes a .multislider bank', () {
    final bank = gateway.createObject(inst, Obj.gMultislider, args: '4');
    expect(gateway.guiValueCount(inst, bank), 4);

    gateway.sendList(inst, bank, 0, '0.1 0.2 0.3 0.4 0.5 0.6');

    expect(gateway.guiValueCount(inst, bank), 6);
    expect(numbers(cellsOf(bank)), [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
  });

  test('a .kslider reports one cell per key', () {
    final keys = gateway.createObject(inst, Obj.gKslider);
    expect(gateway.guiValueCount(inst, keys), 128);
    expect(gateway.setGuiValueAt(inst, keys, 60, '100'), isTrue);
    expect(num.parse(gateway.guiValueAt(inst, keys, 60)), 100);
    expect(num.parse(gateway.guiValueAt(inst, keys, 61)), 0);
  });

  test('a .textedit cell is free text, written whole', () {
    final text = gateway.createObject(inst, Obj.gTextedit);
    expect(gateway.setGuiValueAt(inst, text, 0, 'hello world'), isTrue);
    expect(gateway.guiValueCount(inst, text), 1);
    expect(gateway.guiValueAt(inst, text, 0), 'hello world');
  });

  test('a .b is not settable, so neither write is sent', () {
    final bang = gateway.createObject(inst, Obj.gButton);
    expect(gateway.guiValueIsSettable(inst, bang), isFalse);
    expect(gateway.restoreGuiValue(inst, bang, '1'), isFalse);
    expect(gateway.setGuiValueAt(inst, bang, 0, '1'), isFalse);
  });

  test('a .l stores the list it is sent, but is not settable', () {
    final list = gateway.createObject(inst, Obj.gList);
    gateway.sendList(inst, list, 0, '1 2 three');
    expect(gateway.guiValue(inst, list), '1 2 three');
    expect(gateway.guiValueIsSettable(inst, list), isFalse);
  });

  test('an unknown handle answers the empty protocol', () {
    expect(gateway.guiValueCount(inst, 999), 0);
    expect(gateway.guiValueAt(inst, 999, 0), '');
    expect(gateway.guiValueIsSettable(inst, 999), isFalse);
    expect(gateway.restoreGuiValue(inst, 999, '1'), isFalse);
    expect(gateway.setGuiValueAt(inst, 999, 0, '1'), isFalse);
    gateway.sendList(inst, 999, 0, '1 2');
    gateway.sendMessage(inst, 999, 0, 'clear');
  });
}
