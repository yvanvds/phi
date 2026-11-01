import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_preset_grid.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/preset_grid.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the `.preset` slot grid (issue #477): a click recalls,
/// Shift+click stores and Alt+click clears, each reaching the fake gateway as
/// the message the object takes; the grid shows the active slot from the GUI
/// value and the stored ones from the object's saved state, and follows a
/// store driven over a cable.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  PatchNode addNode(String type, {String args = ''}) {
    final registered = NodeTypeRegistry.instance.find(type)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: type,
        defaultSize: registered.defaultSize,
        sizeForArgs: registered.sizeForArgs,
        defaultArgs: args,
        inputs: registered.inputs,
        outputs: registered.outputs,
        buildBody: registered.buildBody,
        readsGuiValue: registered.readsGuiValue,
        guiValueRead: registered.guiValueRead,
      ),
      position: Offset.zero,
    );
  }

  int handleOf(String type) =>
      gateway.nodes.entries.firstWhere((e) => e.value.type == type).key;

  /// What reached the bank's inlet 0, as messages.
  List<String> sent() => [
    for (final c in gateway.calls)
      if (c.startsWith('sendMessage:${handleOf(Obj.gPreset)}:0:'))
        c.substring('sendMessage:${handleOf(Obj.gPreset)}:0:'.length),
  ];

  PatchPresetGrid grid(WidgetTester tester) =>
      tester.widget<PatchPresetGrid>(find.byType(PatchPresetGrid));

  Future<void> pumpBody(WidgetTester tester, PatchNode node) async {
    final size = node.size;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Builder(
                builder: (context) => NodeTypeRegistry.instance
                    .find(node.type)!
                    .buildBody!(context, node, controller),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The centre of [slot]'s button on screen.
  Offset slotAt(WidgetTester tester, int slot, int slots) {
    final box = tester.getRect(find.byType(PatchPresetGrid));
    final g = PresetGrid(slots: slots, width: box.width, height: box.height);
    final (x, y) = g.originOf(slot);
    return box.topLeft + Offset(x + g.cellWidth / 2, y + g.cellHeight / 2);
  }

  Future<void> click(
    WidgetTester tester,
    int slot, {
    int slots = 32,
    LogicalKeyboardKey? holding,
  }) async {
    if (holding != null) await tester.sendKeyDownEvent(holding);
    await tester.tapAt(slotAt(tester, slot, slots));
    if (holding != null) await tester.sendKeyUpEvent(holding);
    await tester.pump();
  }

  test('registers as a whole-read GUI body sized by its slot count', () {
    final d = NodeTypeRegistry.instance.find(Obj.gPreset)!;
    expect(d.readsGuiValue, isTrue);
    expect(d.guiValueRead, GuiValueRead.whole);
    expect([for (final o in d.outputs) o.label], ['recalled', 'stored']);
    expect(d.inputs, hasLength(1));
    expect(d.defaultSize, const Size(160, 80), reason: 'four rows of eight');
    expect(d.sizeForArgs!('8'), const Size(160, 20));
    expect(d.sizeForArgs!('1024'), const Size(384, 384));
  });

  testWidgets('draws the fresh bank: every slot empty, none active', (
    tester,
  ) async {
    await pumpBody(tester, addNode(Obj.gPreset));
    expect(grid(tester).slots, 32);
    expect(grid(tester).stored, isEmpty);
    expect(grid(tester).active, -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift+click stores, a click recalls and Alt+click clears', (
    tester,
  ) async {
    final slider = addNode(Obj.gSlider);
    final bank = addNode(Obj.gPreset);
    await pumpBody(tester, bank);
    final sliderHandle = handleOf(Obj.gSlider);
    controller.setControlValue(slider.id, inlet: 0, value: 0.25);
    gateway.calls.clear();

    await click(tester, 1, holding: LogicalKeyboardKey.shiftLeft);
    expect(sent(), ['store 1']);
    expect(grid(tester).stored, {1});
    expect(grid(tester).active, 1);

    controller.setControlValue(slider.id, inlet: 0, value: 0.75);
    await click(tester, 1);
    expect(sent().last, 'recall 1');
    expect(gateway.guiValue(controller.instanceId, sliderHandle), '0.25');

    await click(tester, 1, holding: LogicalKeyboardKey.altLeft);
    expect(sent().last, 'clear 1');
    expect(grid(tester).stored, isEmpty);
    expect(grid(tester).active, -1);
  });

  testWidgets('a click on an empty slot recalls nothing and lights nothing', (
    tester,
  ) async {
    final bank = addNode(Obj.gPreset, args: '8');
    await pumpBody(tester, bank);
    await click(tester, 5, slots: 8);
    expect(sent(), ['recall 5']);
    expect(grid(tester).active, -1);
  });

  testWidgets('shows slots it was loaded with, and follows a store over a '
      'cable', (tester) async {
    final slider = addNode(Obj.gSlider);
    controller.setControlValue(slider.id, inlet: 0, value: 0.5);
    final bank = addNode(Obj.gPreset);
    final handle = handleOf(Obj.gPreset);
    // As a reload leaves it: slots restored, slot 4 active, nothing recalled.
    gateway.nodes[handle]!.restorePreset({
      'active': 4,
      'slots': [
        for (final n in [2, 4])
          {
            'slot': n,
            'objects': [
              {'object': 0, 'type': Obj.gSlider, 'value': '0.5'},
            ],
          },
      ],
    }, (rank) => handleOf(Obj.gSlider));
    await pumpBody(tester, bank);
    expect(grid(tester).stored, {2, 4});
    expect(grid(tester).active, 4);

    gateway.sendMessage(controller.instanceId, handle, 0, 'store 9');
    controller.refreshGuiValues();
    await tester.pump();
    expect(grid(tester).stored, {2, 4, 9});
    expect(grid(tester).active, 9);
  });

  testWidgets('shows the modifier hint as its tooltip', (tester) async {
    await pumpBody(tester, addNode(Obj.gPreset));
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message!.contains('Shift+click stores'),
      ),
      findsOneWidget,
    );
  });
}
