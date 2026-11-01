import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
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
/// [pressReadSkip], when set, skips the checks that a momentary control's
/// pending press reads as `1` (a `.b`'s as `on`) — for a gateway that cannot report one yet (the
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

  // A `.b` lights until the host next reads it (issue #519): its read is
  // destructive, spelt `on` / `off`.
  test('a .b reports a press once as on, then off', () {
    final bang = gateway.createObject(inst, Obj.gButton);
    expect(gateway.guiValue(inst, bang), 'off');
    gateway.sendBang(inst, bang, 0);
    expect(gateway.guiValue(inst, bang), 'on', reason: 'the press');
    expect(gateway.guiValue(inst, bang), 'off', reason: 'consumed');
    gateway.sendInt(inst, bang, 0, 3);
    expect(gateway.guiValue(inst, bang), 'on', reason: 'a number too');
    gateway.sendFloat(inst, bang, 0, 0.5);
    expect(gateway.guiValueAt(inst, bang, 0), 'on', reason: 'per cell too');
    expect(gateway.guiValueAt(inst, bang, 0), 'off', reason: 'consumed');
  }, skip: pressReadSkip);

  test('a read of a .b clears its press', () {
    final bang = gateway.createObject(inst, Obj.gButton);
    gateway.sendBang(inst, bang, 0);
    gateway.guiValue(inst, bang);
    expect(gateway.guiValue(inst, bang), 'off');
    gateway.sendBang(inst, bang, 0);
    gateway.guiValueAt(inst, bang, 0);
    expect(gateway.guiValueAt(inst, bang, 0), 'off');
  });

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

  // ─── the multi-value sliders (issue #472) ─────────────────────────────

  /// Wire [from]'s [outlet] into a fresh object of [type]'s inlet 0.
  int listen(int from, int outlet, String type) {
    final to = gateway.createObject(inst, type);
    gateway.connect(
      inst,
      fromHandleId: from,
      outlet: outlet,
      toHandleId: to,
      inlet: 0,
    );
    return to;
  }

  test('an .rslider bounds its ends and reports them low first', () {
    final range = gateway.createObject(inst, Obj.gRslider, args: '20 20000');
    expect(numbers(cellsOf(range)), [20, 20], reason: 'bounded on the way out');

    gateway.sendFloat(inst, range, 0, 500);
    expect(numbers(cellsOf(range)), [20, 500]);
    gateway.sendFloat(inst, range, 1, 100);
    expect(numbers(cellsOf(range)), [100, 500]);
    gateway.sendFloat(inst, range, 0, 50);
    expect(numbers(cellsOf(range)), [50, 100], reason: 'the ends swap');
    gateway.sendList(inst, range, 0, '30000 10');
    expect(numbers(cellsOf(range)), [20, 20000], reason: 'both clamped');
    expect(gateway.setGuiValueAt(inst, range, 0, '64'), isTrue);
    expect(numbers(cellsOf(range)), [64, 20000]);
  });

  test('an .rslider sends low, high and the pair from its hot inlet only', () {
    final range = gateway.createObject(inst, Obj.gRslider);
    final low = listen(range, 0, Obj.gFloat);
    final high = listen(range, 1, Obj.gFloat);
    final pair = listen(range, 2, Obj.gList);

    gateway.sendList(inst, range, 0, '96 32');
    expect(num.parse(gateway.guiValue(inst, low)), 32);
    expect(num.parse(gateway.guiValue(inst, high)), 96);
    expect(numbers(gateway.guiValue(inst, pair).split(' ')), [32, 96]);

    gateway.sendFloat(inst, range, 1, 8);
    expect(
      num.parse(gateway.guiValue(inst, low)),
      32,
      reason: 'inlet 1 is cold',
    );
    // Inlet 1 wrote the other end, the one 32 came from, so 96 is still high.
    gateway.sendBang(inst, range, 0);
    expect(num.parse(gateway.guiValue(inst, low)), 8);
    expect(num.parse(gateway.guiValue(inst, high)), 96);
  });

  test('an .xyslider bounds x and y on their own axes', () {
    final pad = gateway.createObject(inst, Obj.gXyslider, args: '0 1 -1 1');
    expect(gateway.guiValueCount(inst, pad), 2);
    expect(gateway.guiValueIsSettable(inst, pad), isTrue);

    gateway.sendList(inst, pad, 0, '0.5 -0.25');
    expect(numbers(cellsOf(pad)), [0.5, -0.25]);
    gateway.sendList(inst, pad, 0, '2 -5');
    expect(numbers(cellsOf(pad)), [1, -1]);
    expect(gateway.setGuiValueAt(inst, pad, 1, '0.5'), isTrue);
    expect(numbers(cellsOf(pad)), [1, 0.5]);
    gateway.sendFloat(inst, pad, 1, 0.75);
    expect(numbers(cellsOf(pad)), [1, 0.75]);
  });

  test('an .xyslider sends x, y and the pair', () {
    final pad = gateway.createObject(inst, Obj.gXyslider);
    final x = listen(pad, 0, Obj.gFloat);
    final y = listen(pad, 1, Obj.gFloat);
    final pair = listen(pad, 2, Obj.gList);

    gateway.sendList(inst, pad, 0, '12 100');
    expect(num.parse(gateway.guiValue(inst, x)), 12);
    expect(num.parse(gateway.guiValue(inst, y)), 100);
    expect(numbers(gateway.guiValue(inst, pair).split(' ')), [12, 100]);
  });

  test('a .multislider bounds its cells and a number sets every one', () {
    final bank = gateway.createObject(inst, Obj.gMultislider, args: '4 2 10');
    expect(numbers(cellsOf(bank)), [2, 2, 2, 2], reason: 'bounded');

    gateway.sendFloat(inst, bank, 0, 3);
    expect(numbers(cellsOf(bank)), [3, 3, 3, 3]);
    expect(gateway.setGuiValueAt(inst, bank, 2, '12'), isTrue);
    expect(numbers(cellsOf(bank)), [3, 3, 10, 3]);
    expect(gateway.setGuiValueAt(inst, bank, 4, '5'), isFalse);
  });

  test('a .multislider sends its bank, and a fetched cell on outlet 1', () {
    final bank = gateway.createObject(inst, Obj.gMultislider, args: '3');
    final whole = listen(bank, 0, Obj.gList);
    final cell = listen(bank, 1, Obj.gFloat);

    gateway.sendList(inst, bank, 0, '1 2 3');
    expect(numbers(gateway.guiValue(inst, whole).split(' ')), [1, 2, 3]);
    expect(gateway.setGuiValueAt(inst, bank, 1, '64'), isTrue);
    expect(numbers(gateway.guiValue(inst, whole).split(' ')), [1, 64, 3]);

    gateway.sendMessage(inst, bank, 0, 'fetch 1');
    expect(num.parse(gateway.guiValue(inst, cell)), 64);
  });

  test('a .multislider keeps the cells a shorter list hid', () {
    final bank = gateway.createObject(inst, Obj.gMultislider, args: '4');
    gateway.sendList(inst, bank, 0, '1 2 3 4');
    gateway.sendList(inst, bank, 0, '5 6');
    expect(numbers(cellsOf(bank)), [5, 6]);
    gateway.sendList(inst, bank, 0, '7 8 9');
    expect(numbers(cellsOf(bank)), [7, 8, 9]);
  });

  // ─── the keyboard and the staff (issue #473) ─────────────────────────

  test('a .kslider plays a bare pitch at its stored velocity', () {
    final keys = gateway.createObject(inst, Obj.gKslider, args: '90');
    final pitch = listen(keys, 0, Obj.gInt);
    final velocity = listen(keys, 1, Obj.gInt);

    gateway.sendInt(inst, keys, 0, 60);
    expect(gateway.guiValueAt(inst, keys, 60), '90');
    expect(gateway.guiValue(inst, pitch), '60');
    expect(gateway.guiValue(inst, velocity), '90');

    // Inlet 1 stores a velocity for later pitches and sends nothing.
    gateway.sendInt(inst, keys, 1, 30);
    expect(gateway.guiValue(inst, pitch), '60');
    gateway.sendFloat(inst, keys, 0, 64.7);
    expect(gateway.guiValueAt(inst, keys, 64), '30', reason: 'truncated');
    expect(gateway.guiValue(inst, pitch), '64');
    expect(gateway.guiValue(inst, velocity), '30');

    // Velocity 0 releases.
    gateway.sendList(inst, keys, 0, '60 0');
    expect(gateway.guiValueAt(inst, keys, 60), '0');
    expect(gateway.guiValue(inst, velocity), '0');
  });

  test('a .kslider cell write plays that key and sends it', () {
    final keys = gateway.createObject(inst, Obj.gKslider);
    final pitch = listen(keys, 0, Obj.gInt);
    final velocity = listen(keys, 1, Obj.gInt);

    expect(gateway.setGuiValueAt(inst, keys, 72, '200'), isTrue);
    expect(gateway.guiValueAt(inst, keys, 72), '127', reason: 'clamped');
    expect(gateway.guiValue(inst, pitch), '72');
    expect(gateway.guiValue(inst, velocity), '127');

    // A `set` leaves the stored velocity alone: a bare pitch still plays 100.
    gateway.sendInt(inst, keys, 0, 48);
    expect(gateway.guiValueAt(inst, keys, 48), '100');

    expect(gateway.setGuiValueAt(inst, keys, 72, '0'), isTrue);
    expect(gateway.guiValueAt(inst, keys, 72), '0');
    expect(gateway.guiValue(inst, pitch), '72');
    expect(gateway.guiValue(inst, velocity), '0');
  });

  test('a .kslider holds several keys, and clear releases them all', () {
    final keys = gateway.createObject(inst, Obj.gKslider);
    final velocity = listen(keys, 1, Obj.gInt);
    gateway.sendList(inst, keys, 0, '60 80');
    gateway.sendList(inst, keys, 0, '64 90');
    gateway.sendInt(inst, keys, 0, 200);
    expect(gateway.guiValueCount(inst, keys), 128);
    final held = {
      for (final (i, c) in cellsOf(keys).indexed)
        if (c != '0') i: c,
    };
    expect(held, {60: '80', 64: '90'}, reason: 'off the keyboard: dropped');

    gateway.sendMessage(inst, keys, 0, 'clear');
    expect(cellsOf(keys).every((c) => c == '0'), isTrue);
    expect(gateway.guiValue(inst, velocity), '0');
  });

  test('a .nslider stores a pitch and spells it', () {
    final staff = gateway.createObject(inst, Obj.gNslider, args: '36 96 -1');
    final pitch = listen(staff, 0, Obj.gInt);
    final accidental = listen(staff, 1, Obj.gInt);
    expect(gateway.guiValueCount(inst, staff), 2);
    expect(gateway.guiValueIsSettable(inst, staff), isTrue);
    expect(numbers(cellsOf(staff)), [36, 0], reason: 'the bottom of its range');

    gateway.sendInt(inst, staff, 0, 61);
    expect(numbers(cellsOf(staff)), [61, -1], reason: 'spelled flat');
    expect(gateway.guiValue(inst, pitch), '61');
    expect(gateway.guiValue(inst, accidental), '-1');

    gateway.sendList(inst, staff, 0, '61 1');
    expect(numbers(cellsOf(staff)), [61, 1]);
    expect(gateway.guiValue(inst, accidental), '1');

    gateway.sendInt(inst, staff, 0, 63);
    expect(numbers(cellsOf(staff)), [63, -1], reason: 'the key is unchanged');

    gateway.sendInt(inst, staff, 0, 10);
    expect(numbers(cellsOf(staff)), [36, 0], reason: 'clamped');
    expect(gateway.guiValue(inst, pitch), '36');

    expect(gateway.setGuiValueAt(inst, staff, 0, '66'), isTrue);
    expect(numbers(cellsOf(staff)), [66, -1]);
    expect(gateway.setGuiValueAt(inst, staff, 1, '1'), isTrue);
    expect(numbers(cellsOf(staff)), [66, 1]);
    expect(gateway.guiValue(inst, pitch), '66', reason: 'a set sends too');
    // A live re-range is deferred to the audio thread in the engine (the
    // scalar plan), so it is not pinned here.
  });

  // ─── the grid (issue #474) ────────────────────────────────────────────

  test('a .matrixctrl holds a cell per grid cell, column-major', () {
    final grid = gateway.createObject(inst, Obj.gMatrixctrl, args: '3 2 0 4');
    final cell = listen(grid, 0, Obj.gList);
    expect(gateway.guiValueCount(inst, grid), 6);
    expect(gateway.guiValueIsSettable(inst, grid), isTrue);
    expect(numbers(cellsOf(grid)), [0, 0, 0, 0, 0, 0]);

    // Column 2, row 1 is index 2 * 2 + 1.
    gateway.sendList(inst, grid, 0, '2 1 3');
    expect(numbers(cellsOf(grid)), [0, 0, 0, 0, 0, 3]);
    expect(numbers(gateway.guiValue(inst, cell).split(' ')), [2, 1, 3]);

    // A cell write is `set <index> <value>`, bounded, and sent as a triple.
    expect(gateway.setGuiValueAt(inst, grid, 1, '9'), isTrue);
    expect(numbers(cellsOf(grid)), [0, 4, 0, 0, 0, 3], reason: 'clamped');
    expect(numbers(gateway.guiValue(inst, cell).split(' ')), [0, 1, 4]);
    expect(gateway.setGuiValueAt(inst, grid, 6, '1'), isFalse);

    // A cell off the grid is dropped.
    gateway.sendList(inst, grid, 0, '3 0 1');
    expect(numbers(cellsOf(grid)), [0, 4, 0, 0, 0, 3]);
  });

  test('a .matrixctrl defaults to 8 x 8 on and off, and starts at its '
      'minimum', () {
    final grid = gateway.createObject(inst, Obj.gMatrixctrl);
    expect(gateway.guiValueCount(inst, grid), 64);
    gateway.sendList(inst, grid, 0, '7 7 5');
    expect(num.parse(gateway.guiValueAt(inst, grid, 63)), 1);

    final raised = gateway.createObject(inst, Obj.gMatrixctrl, args: '2 2 1 3');
    expect(numbers(cellsOf(raised)), [1, 1, 1, 1]);
  });

  test('a .matrixctrl takes a whole grid, clears, and answers a row or '
      'column on outlet 1', () {
    final grid = gateway.createObject(inst, Obj.gMatrixctrl, args: '2 3 0 9');
    final cell = listen(grid, 0, Obj.gList);
    final line = listen(grid, 1, Obj.gList);

    expect(gateway.restoreGuiValue(inst, grid, '1 2 3 4 5 6'), isTrue);
    expect(numbers(cellsOf(grid)), [1, 2, 3, 4, 5, 6]);
    // Every cell is sent, the last one last.
    expect(numbers(gateway.guiValue(inst, cell).split(' ')), [1, 2, 6]);

    gateway.sendMessage(inst, grid, 0, 'getrow 1');
    expect(numbers(gateway.guiValue(inst, line).split(' ')), [2, 5]);
    gateway.sendMessage(inst, grid, 0, 'getcolumn 0');
    expect(numbers(gateway.guiValue(inst, line).split(' ')), [1, 2, 3]);

    gateway.sendList(inst, grid, 0, '0 2 7');
    gateway.sendBang(inst, grid, 0);
    expect(numbers(gateway.guiValue(inst, cell).split(' ')), [1, 2, 6]);

    gateway.sendMessage(inst, grid, 0, 'clear');
    expect(numbers(cellsOf(grid)), [0, 0, 0, 0, 0, 0]);
    expect(numbers(gateway.guiValue(inst, cell).split(' ')), [1, 2, 0]);
  });

  // ─── the breakpoint function (issue #475) ─────────────────────────────

  List<List<num?>> pointsOf(int handle) => [
    for (final cell in cellsOf(handle)) numbers(cell.split(' ')),
  ];

  test('a .function holds a sorted <x> <y> <curve> cell per point', () {
    final fn = gateway.createObject(inst, Obj.gFunction, args: '8 0 2');
    expect(gateway.guiValueCount(inst, fn), 0, reason: 'starts empty');
    expect(gateway.guiValue(inst, fn), 'clear');
    expect(gateway.guiValueIsSettable(inst, fn), isTrue);

    // Two numbers add a point, in x order, y bounded, curve 0.
    gateway.sendList(inst, fn, 0, '500 1.5');
    gateway.sendList(inst, fn, 0, '0 0.25');
    gateway.sendList(inst, fn, 0, '250 9');
    expect(pointsOf(fn), [
      [0, 0.25, 0],
      [250, 2, 0],
      [500, 1.5, 0],
    ]);

    // The cell write is `set <i> <x> <y>`, keeping the curve; a point at an
    // existing x replaces it.
    gateway.sendMessage(inst, fn, 0, 'setcurve 2 0.5');
    expect(gateway.setGuiValueAt(inst, fn, 2, '750 1'), isTrue);
    expect(pointsOf(fn).last, [750, 1, 0.5]);
    expect(gateway.setGuiValueAt(inst, fn, 3, '1 1'), isFalse);
    gateway.sendList(inst, fn, 0, '250 0.5');
    expect(pointsOf(fn)[1], [250, 0.5, 0]);

    // `clear <i>` removes one point, `clear` all of them.
    gateway.sendMessage(inst, fn, 0, 'clear 1');
    expect(pointsOf(fn), [
      [0, 0.25, 0],
      [750, 1, 0.5],
    ]);
    gateway.sendMessage(inst, fn, 0, 'clear');
    expect(gateway.guiValueCount(inst, fn), 0);
  });

  test('a .function takes its whole state back and refuses a point past its '
      'capacity', () {
    final fn = gateway.createObject(inst, Obj.gFunction, args: '2');
    expect(gateway.restoreGuiValue(inst, fn, '100 0.5 -0.5 0 0.25 0'), isTrue);
    expect(pointsOf(fn), [
      [0, 0.25, 0],
      [100, 0.5, -0.5],
    ]);
    gateway.sendList(inst, fn, 0, '50 1');
    expect(gateway.guiValueCount(inst, fn), 2, reason: 'the store is full');

    final saved = gateway.guiValue(inst, fn);
    gateway.sendMessage(inst, fn, 0, 'clear');
    gateway.restoreGuiValue(inst, fn, saved);
    expect(pointsOf(fn), [
      [0, 0.25, 0],
      [100, 0.5, -0.5],
    ]);
  });

  test('a .function answers an x on outlet 0, a bang with its ramp on outlet '
      '1, and dump on outlet 2', () {
    final fn = gateway.createObject(inst, Obj.gFunction);
    final y = listen(fn, 0, Obj.gFloat);
    final ramp = listen(fn, 1, Obj.gList);
    final dump = listen(fn, 2, Obj.gList);
    gateway.restoreGuiValue(inst, fn, '0 0 0 100 1 0 300 0.5 0');

    gateway.sendFloat(inst, fn, 0, 50);
    expect(num.parse(gateway.guiValue(inst, y)), 0.5);
    gateway.sendInt(inst, fn, 0, 200);
    expect(num.parse(gateway.guiValue(inst, y)), 0.75);
    gateway.sendFloat(inst, fn, 0, 1000);
    expect(num.parse(gateway.guiValue(inst, y)), 0.5, reason: 'past the end');
    gateway.sendMessage(inst, fn, 0, 'nth 1');
    expect(num.parse(gateway.guiValue(inst, y)), 1);

    // A curve bends the query, not the ramp.
    gateway.sendMessage(inst, fn, 0, 'setcurve 1 0.5');
    gateway.sendFloat(inst, fn, 0, 50);
    expect(num.parse(gateway.guiValue(inst, y)), closeTo(0.125, 1e-4));

    gateway.sendBang(inst, fn, 0);
    expect(numbers(gateway.guiValue(inst, ramp).split(' ')), [
      0,
      0,
      1,
      100,
      0.5,
      200,
    ]);

    gateway.sendMessage(inst, fn, 0, 'dump');
    expect(numbers(gateway.guiValue(inst, dump).split(' ')), [2, 300, 0.5, 0]);
  });

  test('a .function sends nothing on an edit', () {
    final fn = gateway.createObject(inst, Obj.gFunction);
    final y = listen(fn, 0, Obj.gFloat);
    final ramp = listen(fn, 1, Obj.gList);
    gateway.sendList(inst, fn, 0, '0 1');
    gateway.sendList(inst, fn, 0, '10 0');
    gateway.setGuiValueAt(inst, fn, 1, '20 0.5');
    gateway.sendMessage(inst, fn, 0, 'setcurve 1 0.5');
    expect(num.tryParse(gateway.guiValue(inst, y)) ?? 0, 0);
    expect(gateway.guiValue(inst, ramp), isEmpty);
  });

  test('a .function keeps its points through a dump and a reload', () {
    final fn = gateway.createObject(inst, Obj.gFunction, args: '16 0 10');
    gateway.restoreGuiValue(inst, fn, '0 2 0 40 8 0.5 100 0 -0.25');
    final dump = gateway.dumpJson(inst);

    final copy = gateway.createInstance();
    gateway.parseJson(copy, dump);
    final reloaded = gateway
        .enumerate(copy)
        .objects
        .firstWhere((o) => o.type == Obj.gFunction)
        .handleId;
    expect(
      [
        for (var i = 0; i < gateway.guiValueCount(copy, reloaded); i++)
          numbers(gateway.guiValueAt(copy, reloaded, i).split(' ')),
      ],
      [
        [0, 2, 0],
        [40, 8, 0.5],
        [100, 0, -0.25],
      ],
    );
  });

  // ─── the interpolation field (issue #476) ─────────────────────────────

  List<List<num?>> fieldOf(int handle) => [
    for (final cell in cellsOf(handle)) numbers(cell.split(' ')),
  ];

  List<double> listOf(int handle) => [
    for (final n in gateway.guiValue(inst, handle).trim().split(' '))
      double.parse(n),
  ];

  test('a .nodes holds an <x> <y> <radius> cell per node, unit nodes at the '
      'origin to start', () {
    final field = gateway.createObject(inst, Obj.gNodes);
    expect(fieldOf(field), List.filled(4, [0, 0, 1]));
    expect(gateway.guiValueIsSettable(inst, field), isTrue);
    expect(numbers(gateway.guiValue(inst, field).split(' ')), [
      for (var i = 0; i < 4; i++) ...[0, 0, 1],
    ]);

    expect(
      fieldOf(gateway.createObject(inst, Obj.gNodes, args: '2')),
      List.filled(2, [0, 0, 1]),
    );
    expect(
      gateway.guiValueCount(
        inst,
        gateway.createObject(inst, Obj.gNodes, args: '99'),
      ),
      64,
      reason: 'the count is clamped to 64',
    );
    expect(
      gateway.guiValueCount(
        inst,
        gateway.createObject(inst, Obj.gNodes, args: '0'),
      ),
      1,
      reason: 'and to at least 1',
    );
  });

  test('a .nodes takes a whole field back, resizing to its triples, and moves '
      'one node with the cell write', () {
    final field = gateway.createObject(inst, Obj.gNodes);
    // A trailing partial triple is ignored.
    expect(
      gateway.restoreGuiValue(
        inst,
        field,
        '0.25 0.25 0.5 0.75 0.75 0.25 0.5 0.5',
      ),
      isTrue,
    );
    expect(fieldOf(field), [
      [0.25, 0.25, 0.5],
      [0.75, 0.75, 0.25],
    ]);

    // `set <i> <x> <y>` keeps the radius; a fourth number replaces it.
    expect(gateway.setGuiValueAt(inst, field, 1, '0.5 0.5'), isTrue);
    expect(fieldOf(field)[1], [0.5, 0.5, 0.25]);
    expect(gateway.setGuiValueAt(inst, field, 0, '0 1 0.125'), isTrue);
    expect(fieldOf(field)[0], [0, 1, 0.125]);
    expect(gateway.setGuiValueAt(inst, field, 2, '0.5 0.5'), isFalse);
    expect(fieldOf(field), hasLength(2));

    // A longer field grows the count past the creation argument.
    final small = gateway.createObject(inst, Obj.gNodes, args: '2');
    gateway.sendList(inst, small, 0, '0 0 0.5 0.5 0 0.5 1 0 0.5');
    expect(fieldOf(small), hasLength(3));

    final saved = gateway.guiValue(inst, field);
    gateway.restoreGuiValue(inst, field, '0 0 1');
    expect(fieldOf(field), hasLength(1));
    gateway.restoreGuiValue(inst, field, saved);
    expect(fieldOf(field), [
      [0, 1, 0.125],
      [0.5, 0.5, 0.25],
    ]);
  });

  test('a .nodes weighs the cursor: weights on outlet 0 summing to 1 inside '
      'a node, all 0 outside, distances on outlet 1', () {
    final field = gateway.createObject(inst, Obj.gNodes, args: '2');
    final weights = listen(field, 0, Obj.gList);
    final distances = listen(field, 1, Obj.gList);
    gateway.restoreGuiValue(inst, field, '0 0 1 1 0 1');

    gateway.sendList(inst, field, 0, '0.25 0');
    expect(listOf(weights), [closeTo(0.75, 1e-6), closeTo(0.25, 1e-6)]);
    expect(listOf(distances), [closeTo(0.25, 1e-6), closeTo(0.75, 1e-6)]);

    // Inside only the first node.
    gateway.restoreGuiValue(inst, field, '0.25 0.25 0.2 0.75 0.75 0.2');
    gateway.sendList(inst, field, 0, '0.25 0.25');
    expect(listOf(weights), [1, 0]);
    expect(listOf(distances), [0, closeTo(0.7071068, 1e-5)]);

    // Outside every node.
    gateway.sendList(inst, field, 0, '0.5 0.5');
    expect(listOf(weights), [0, 0]);

    // A muted node (radius 0) covers nothing.
    gateway.restoreGuiValue(inst, field, '0.5 0.5 0 0.5 0.5 1');
    gateway.sendList(inst, field, 0, '0.5 0.5');
    expect(listOf(weights), [0, 1]);
  });

  test('a .nodes sends the distances first and the weights last, after every '
      'list, set and bang, but not on a bare number', () {
    final field = gateway.createObject(inst, Obj.gNodes, args: '2');
    final last = listen(field, 0, Obj.gList);
    gateway.connect(
      inst,
      fromHandleId: field,
      outlet: 1,
      toHandleId: last,
      inlet: 0,
    );
    gateway.restoreGuiValue(inst, field, '0.25 0.25 0.2 0.75 0.75 0.2');
    gateway.sendList(inst, field, 0, '0.75 0.75');
    expect(listOf(last), [0, 1], reason: 'the weights arrive last');

    gateway.sendList(inst, last, 0, '9');
    gateway.sendFloat(inst, field, 0, 0.3);
    gateway.sendInt(inst, field, 0, 1);
    expect(listOf(last), [9], reason: 'no number handler');

    gateway.sendBang(inst, field, 0);
    expect(listOf(last), [0, 1], reason: 'a bang re-sends');

    gateway.sendList(inst, last, 0, '9');
    gateway.setGuiValueAt(inst, field, 0, '0.75 0.75');
    expect(listOf(last), [0.5, 0.5], reason: 'a node move sends');

    gateway.sendList(inst, last, 0, '9');
    gateway.sendMessage(inst, field, 0, 'set 1 0 0 0.1');
    expect(listOf(last), [1, 0], reason: 'so does a set message');
  });

  // TODO(yvanvds/yse-soundengine#1228): .nodes has no DumpState yet; flip this
  // to expect the layout back once the engine saves it under `state`.
  test('a .nodes saves only its count: a reload is that many fresh nodes', () {
    final field = gateway.createObject(inst, Obj.gNodes, args: '3');
    gateway.restoreGuiValue(inst, field, '0.25 0.25 0.5 0.75 0.75 0.25');
    final dump = gateway.dumpJson(inst);

    final copy = gateway.createInstance();
    gateway.parseJson(copy, dump);
    final reloaded = gateway
        .enumerate(copy)
        .objects
        .firstWhere((o) => o.type == Obj.gNodes)
        .handleId;
    expect([
      for (var i = 0; i < gateway.guiValueCount(copy, reloaded); i++)
        numbers(gateway.guiValueAt(copy, reloaded, i).split(' ')),
    ], List.filled(3, [0, 0, 1]));
  });

  // ─── the preset bank (issue #477) ──────────────────────────────────────

  test('a .preset is one inlet, two outlets, and a read-only active slot', () {
    final bank = gateway.createObject(inst, Obj.gPreset);
    final ports = gateway.inspect(inst, bank);
    expect(ports.inputs, 1);
    expect(ports.outputs, 2);
    expect(ports.outputKinds, everyElement(PatchPortKind.control));
    expect(gateway.guiValue(inst, bank), '-1', reason: 'no slot active');
    expect(cellsOf(bank), ['-1']);
    expect(gateway.guiValueIsSettable(inst, bank), isFalse);
    expect(gateway.objectState(inst, bank), isNull, reason: 'saves nothing');
  });

  test('a .preset stores the settable controls and recalls them, announcing '
      'the slot stored on outlet 1 and the slot recalled on outlet 0', () {
    final slider = gateway.createObject(inst, Obj.gSlider);
    final number = gateway.createObject(inst, Obj.gInt);
    final bank = gateway.createObject(inst, Obj.gPreset, args: '8');
    final recalled = listen(bank, 0, Obj.gInt);
    final stored = listen(bank, 1, Obj.gInt);
    gateway
      ..sendInt(inst, recalled, 0, 99)
      ..sendInt(inst, stored, 0, 99)
      ..sendFloat(inst, slider, 0, 0.3)
      ..sendInt(inst, number, 0, 7)
      ..sendMessage(inst, bank, 0, 'store 2');

    expect(gateway.guiValue(inst, bank), '2', reason: 'the store is active');
    expect(gateway.guiValue(inst, stored), '2');
    expect(gateway.guiValue(inst, recalled), '99', reason: 'nothing recalled');

    gateway
      ..sendFloat(inst, slider, 0, 0.9)
      ..sendInt(inst, number, 0, 1)
      ..sendInt(inst, stored, 0, 99)
      ..sendInt(inst, bank, 0, 2);
    expect(num.parse(gateway.guiValue(inst, slider)), closeTo(0.3, 1e-6));
    expect(gateway.guiValue(inst, number), '7');
    expect(gateway.guiValue(inst, recalled), '2');
    expect(gateway.guiValue(inst, stored), '99', reason: 'nothing stored');
  });

  test('a .preset recalls through every spelling, and an empty or '
      'out-of-range slot does nothing', () {
    final slider = gateway.createObject(inst, Obj.gSlider);
    final bank = gateway.createObject(inst, Obj.gPreset, args: '8');
    final recalled = listen(bank, 0, Obj.gInt);
    gateway
      ..sendFloat(inst, slider, 0, 0.25)
      ..sendMessage(inst, bank, 0, 'store 1')
      ..sendFloat(inst, slider, 0, 0.75)
      ..sendMessage(inst, bank, 0, 'store 3');

    double slid() => num.parse(gateway.guiValue(inst, slider)).toDouble();

    gateway.sendList(inst, bank, 0, 'recall 1');
    expect(slid(), closeTo(0.25, 1e-6));
    gateway.sendFloat(inst, bank, 0, 3.9);
    expect(slid(), closeTo(0.75, 1e-6), reason: 'a float is truncated');
    gateway.sendList(inst, bank, 0, '1');
    expect(slid(), closeTo(0.25, 1e-6), reason: 'a bare number recalls');
    gateway.sendFloat(inst, slider, 0, 0.5);
    gateway.sendBang(inst, bank, 0);
    expect(slid(), closeTo(0.25, 1e-6), reason: 'a bang recalls the active');

    gateway
      ..sendInt(inst, recalled, 0, 99)
      ..sendFloat(inst, slider, 0, 0.5);
    for (final miss in ['recall 5', 'recall 8', 'recall -1', 'recall']) {
      gateway.sendMessage(inst, bank, 0, miss);
    }
    gateway.sendInt(inst, bank, 0, 20);
    expect(slid(), closeTo(0.5, 1e-6));
    expect(gateway.guiValue(inst, recalled), '99', reason: 'announces nothing');
    expect(gateway.guiValue(inst, bank), '1', reason: 'the marker stays');

    gateway.sendMessage(inst, bank, 0, 'store 8');
    expect(gateway.guiValue(inst, bank), '1', reason: 'past the bank');
  });

  test('a .preset clears one slot, the active one, or all of them', () {
    gateway.sendFloat(inst, gateway.createObject(inst, Obj.gSlider), 0, 0.5);
    final bank = gateway.createObject(inst, Obj.gPreset);
    Set<int> slots() => {
      for (final s
          in (gateway.objectState(inst, bank)?['slots'] as List?) ?? const [])
        ((s as Map)['slot'] as num).toInt(),
    };
    for (final n in [0, 4, 6]) {
      gateway.sendMessage(inst, bank, 0, 'store $n');
    }
    expect(slots(), {0, 4, 6});
    expect(gateway.objectState(inst, bank)?['active'], 6);

    gateway.sendMessage(inst, bank, 0, 'clear 4');
    expect(slots(), {0, 6});
    expect(gateway.guiValue(inst, bank), '6', reason: 'another slot cleared');
    gateway.sendMessage(inst, bank, 0, 'clear');
    expect(slots(), {0});
    expect(gateway.guiValue(inst, bank), '-1', reason: 'the active cleared');
    gateway.sendMessage(inst, bank, 0, 'recall 0');
    gateway.sendMessage(inst, bank, 0, 'clearall');
    expect(slots(), isEmpty);
    expect(gateway.guiValue(inst, bank), '-1');
    expect(gateway.objectState(inst, bank), isNull);
  });

  test('a .preset captures neither a .b, a .l nor itself, and a store with '
      'nothing to capture only moves the marker', () {
    final bank = gateway.createObject(inst, Obj.gPreset);
    gateway.sendMessage(inst, bank, 0, 'store 3');
    expect(gateway.guiValue(inst, bank), '3');
    expect(gateway.objectState(inst, bank), {'active': 3});

    gateway.createObject(inst, Obj.gButton);
    gateway.sendList(inst, gateway.createObject(inst, Obj.gList), 0, '1 2');
    gateway.createObject(inst, Obj.gPreset);
    gateway.sendMessage(inst, bank, 0, 'store 3');
    expect(gateway.objectState(inst, bank), {'active': 3});

    final slider = gateway.createObject(inst, Obj.gSlider);
    gateway
      ..sendFloat(inst, slider, 0, 0.5)
      ..sendMessage(inst, bank, 0, 'store 3');
    final objects =
        ((gateway.objectState(inst, bank)!['slots'] as List).single
                as Map)['objects']
            as List;
    expect([for (final o in objects) (o as Map)['type']], [Obj.gSlider]);
  });

  test('a .preset re-ranged by setParams starts with empty slots', () {
    gateway.sendFloat(inst, gateway.createObject(inst, Obj.gSlider), 0, 0.5);
    final bank = gateway.createObject(inst, Obj.gPreset);
    gateway.sendMessage(inst, bank, 0, 'store 2');
    gateway.setParams(inst, bank, '4');
    expect(gateway.guiValue(inst, bank), '-1');
    expect(gateway.objectState(inst, bank), isNull);
    gateway.sendMessage(inst, bank, 0, 'store 5');
    expect(gateway.guiValue(inst, bank), '-1', reason: 'only 4 slots now');
  });

  test('a .preset keeps its slots through a dump and a reload, by object '
      'rank, dropping a deleted object', () {
    final gone = gateway.createObject(inst, Obj.gInt);
    final slider = gateway.createObject(inst, Obj.gSlider);
    final bank = gateway.createObject(inst, Obj.gPreset);
    gateway
      ..sendInt(inst, gone, 0, 3)
      ..sendFloat(inst, slider, 0, 0.25)
      ..sendMessage(inst, bank, 0, 'store 1')
      ..sendMessage(inst, bank, 0, 'store 2')
      ..sendMessage(inst, bank, 0, 'recall 1');
    gateway.deleteObject(inst, gone);
    final dump = gateway.dumpJson(inst);

    final copy = gateway.createInstance();
    gateway.parseJson(copy, dump);
    final objects = gateway.enumerate(copy).objects;
    final reloaded = objects.firstWhere((o) => o.type == Obj.gPreset).handleId;
    final copied = objects.firstWhere((o) => o.type == Obj.gSlider).handleId;

    final state = gateway.objectState(copy, reloaded)!;
    expect(state['active'], 1, reason: 'loading recalls nothing');
    expect(gateway.guiValue(copy, reloaded), '1');
    final slots = state['slots'] as List;
    expect([for (final s in slots) (s as Map)['slot']], [1, 2]);
    expect(
      [
        for (final o in (slots.first as Map)['objects'] as List)
          (o as Map)['type'],
      ],
      [Obj.gSlider],
      reason: 'the deleted .i is dropped',
    );

    gateway.sendFloat(inst, copied, 0, 0.9);
    gateway.sendFloat(copy, copied, 0, 0.9);
    gateway.sendInt(copy, reloaded, 0, 2);
    expect(num.parse(gateway.guiValue(copy, copied)), closeTo(0.25, 1e-6));
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
