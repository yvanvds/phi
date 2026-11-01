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
///
/// [pressReadSkip], when set, skips the check that a momentary control's
/// pending press reads as `1` — for a gateway that cannot report one yet (the
/// real one, until yvanvds/dart-yse#106 reads the native value only once). The
/// check that the read then clears the press runs regardless.
void guiValueProtocolContract(
  PatcherGateway Function() makeGateway, {
  String? pressReadSkip,
}) {
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

  // ─── the single-value control bodies (issue #470) ──────────────────

  test('.incdec steps by its step argument inside a clamped range', () {
    final stepper = gateway.createObject(inst, Obj.gIncdec, args: '2 0 5 0');
    expect(num.parse(gateway.guiValue(inst, stepper)), 0);
    for (var i = 0; i < 4; i++) {
      gateway.sendMessage(inst, stepper, 0, 'inc');
    }
    expect(gateway.guiValue(inst, stepper), '5', reason: 'clamped at max');
    gateway.sendMessage(inst, stepper, 0, 'dec');
    expect(gateway.guiValue(inst, stepper), '3');
  });

  test('.incdec wraps when asked to', () {
    final stepper = gateway.createObject(inst, Obj.gIncdec, args: '1 0 2 1');
    for (var i = 0; i < 3; i++) {
      gateway.sendMessage(inst, stepper, 0, 'inc');
    }
    expect(gateway.guiValue(inst, stepper), '0');
    gateway.sendMessage(inst, stepper, 0, 'dec');
    expect(gateway.guiValue(inst, stepper), '2');
  });

  test('a .dial reports its position, clamped to 0-1', () {
    final dial = gateway.createObject(inst, Obj.gDial, args: '0 127 1 1');
    gateway.sendFloat(inst, dial, 0, 0.25);
    expect(num.parse(gateway.guiValue(inst, dial)), 0.25);
    gateway.sendFloat(inst, dial, 0, 2);
    expect(num.parse(gateway.guiValue(inst, dial)), 1);
    expect(gateway.guiValueIsSettable(inst, dial), isTrue);
  });

  for (final type in [Obj.gLed, Obj.gTextbutton]) {
    test('a latching $type takes an int as its state and flips on a bang', () {
      final lamp = gateway.createObject(inst, type, args: 'mute');
      gateway.sendInt(inst, lamp, 0, 1);
      expect(gateway.guiValue(inst, lamp), '1');
      gateway.sendBang(inst, lamp, 0);
      expect(gateway.guiValue(inst, lamp), '0');
      gateway.sendBang(inst, lamp, 0);
      expect(gateway.guiValue(inst, lamp), '1');
      gateway.sendInt(inst, lamp, 0, 0);
      expect(gateway.guiValue(inst, lamp), '0');
    });
  }

  for (final type in [Obj.gLed, Obj.gTextbutton]) {
    // The engine's momentary read is destructive (issue #514): a press is
    // reported once, then cleared, so a host must read it once per frame.
    test('a momentary $type reports a press once, then idle', () {
      final lamp = gateway.createObject(inst, type, args: 'momentary go');
      expect(gateway.guiValue(inst, lamp), '0');
      gateway.sendInt(inst, lamp, 0, 1);
      expect(gateway.guiValue(inst, lamp), '1', reason: 'the press');
      expect(gateway.guiValue(inst, lamp), '0', reason: 'consumed');
      gateway.sendBang(inst, lamp, 0);
      expect(gateway.guiValueAt(inst, lamp, 0), '1', reason: 'a bang too');
      expect(gateway.guiValueAt(inst, lamp, 0), '0', reason: 'consumed');
    }, skip: pressReadSkip);

    test('a read of a momentary $type clears its press', () {
      final lamp = gateway.createObject(inst, type, args: 'momentary go');
      gateway.sendInt(inst, lamp, 0, 0);
      gateway.guiValue(inst, lamp);
      expect(gateway.guiValue(inst, lamp), '0');
      gateway.sendBang(inst, lamp, 0);
      gateway.guiValueAt(inst, lamp, 0);
      expect(gateway.guiValueAt(inst, lamp, 0), '0');
    });
  }

  test('a .textedit starts with its text and takes a whole new one back', () {
    final text = gateway.createObject(inst, Obj.gTextedit, args: 'hello world');
    expect(gateway.guiValue(inst, text), 'hello world');
    expect(gateway.restoreGuiValue(inst, text, 'foo bar'), isTrue);
    expect(gateway.guiValue(inst, text), 'foo bar');
  });

  // ─── the selection controls (issue #471) ─────────────────────────────

  for (final type in [Obj.gUmenu, Obj.gRadiogroup, Obj.gTab]) {
    test('a single-select $type holds one index, picked by number or name', () {
      final menu = gateway.createObject(inst, type, args: 'sine square saw');
      expect(gateway.guiValueCount(inst, menu), 1);
      expect(gateway.guiValue(inst, menu), '0');
      expect(gateway.guiValueIsSettable(inst, menu), isTrue);

      gateway.sendInt(inst, menu, 0, 2);
      expect(gateway.guiValue(inst, menu), '2');
      gateway.sendFloat(inst, menu, 0, 1);
      expect(gateway.guiValue(inst, menu), '1');
      gateway.sendList(inst, menu, 0, 'saw');
      expect(gateway.guiValue(inst, menu), '2');
      gateway.sendInt(inst, menu, 0, 7);
      expect(gateway.guiValue(inst, menu), '2', reason: 'no item 7');
      gateway.sendList(inst, menu, 0, 'triangle');
      expect(gateway.guiValue(inst, menu), '2', reason: 'no such name');
      expect(gateway.setGuiValueAt(inst, menu, 0, '0'), isTrue);
      expect(gateway.guiValueAt(inst, menu, 0), '0');
    });
  }

  for (final type in [Obj.gUmenu, Obj.gRadiogroup, Obj.gTab]) {
    test('a multi $type has a flag per item, and a number toggles one', () {
      final group = gateway.createObject(inst, type, args: 'multi 4');
      expect(gateway.guiValueCount(inst, group), 4);
      expect(gateway.guiValue(inst, group), '0 0 0 0');

      gateway.sendInt(inst, group, 0, 1);
      gateway.sendInt(inst, group, 0, 3);
      expect(gateway.guiValue(inst, group), '0 1 0 1');
      gateway.sendInt(inst, group, 0, 1);
      expect(gateway.guiValue(inst, group), '0 0 0 1', reason: 'toggled off');
      expect(gateway.guiValueAt(inst, group, 3), '1');

      expect(gateway.restoreGuiValue(inst, group, '1 1 0 0'), isTrue);
      expect(gateway.guiValue(inst, group), '1 1 0 0');
      expect(gateway.setGuiValueAt(inst, group, 3, '1'), isTrue);
      expect(gateway.guiValue(inst, group), '1 1 0 1');
    });
  }

  test('an item list sends the item number down outlet 0', () {
    final menu = gateway.createObject(inst, Obj.gUmenu, args: 'a b c');
    final number = gateway.createObject(inst, Obj.gInt);
    gateway.connect(
      inst,
      fromHandleId: menu,
      outlet: 0,
      toHandleId: number,
      inlet: 0,
    );
    gateway.sendInt(inst, menu, 0, 2);
    expect(gateway.guiValue(inst, number), '2');
    gateway.sendList(inst, menu, 0, 'b');
    expect(gateway.guiValue(inst, number), '1');
  });

  test('new items rebuild an item list at item 0', () {
    final tabs = gateway.createObject(inst, Obj.gTab, args: 'a b c');
    gateway.sendInt(inst, tabs, 0, 2);
    gateway.setParams(inst, tabs, 'multi w x y z');
    expect(gateway.guiValueCount(inst, tabs), 4);
    expect(gateway.guiValue(inst, tabs), '0 0 0 0');
    gateway.setParams(inst, tabs, '');
    expect(gateway.guiValueCount(inst, tabs), 1);
    expect(gateway.guiValue(inst, tabs), '0');
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
