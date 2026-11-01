import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/keyboard_layout.dart';
import 'package:phi/domain/patcher/patch_gui_property.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// A `.kslider`'s range and fixed velocity edited from the editor (issue
/// #515): each edit is one journaled step on the patch's undo, the box follows
/// the range, and the default range is stored as no range at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  PatchNode add(String type) => controller.addNode(
    desc: NodeTypeRegistry.instance.find(type)!,
    position: Offset.zero,
  );

  String gui(PatchNode node, String key) =>
      controller.guiPropertyOf(node.id, key);

  test('a range edit moves both ends in one undoable step, and the box '
      'follows the keys it shows', () {
    final node = add(Obj.gKslider);
    final standard = controller.keyboardLayoutOf(node.id);
    expect(standard.isDefault, isTrue);
    final width = node.size.width;

    controller.setKeyboardRange(node.id, standard.shifted(1)!);
    expect(gui(node, PatchGuiProperty.keyLow), '60');
    expect(gui(node, PatchGuiProperty.keyHigh), '96');
    expect(node.size.width, width, reason: 'same number of keys');

    controller.setKeyboardRange(
      node.id,
      controller.keyboardLayoutOf(node.id).movedLow(-2)!,
    );
    final wide = controller.keyboardLayoutOf(node.id);
    expect((wide.low, wide.high), (36, 96));
    expect(node.size.width, width * 36 / 22, reason: '36 white keys');

    controller.undoScope.undo();
    expect(controller.keyboardLayoutOf(node.id).low, 60);
    expect(node.size.width, width);
    controller.undoScope.undo();
    expect(gui(node, PatchGuiProperty.keyLow), '');
    expect(gui(node, PatchGuiProperty.keyHigh), '');
    expect(controller.undoScope.canUndo, isFalse);

    controller.undoScope.redo();
    expect(controller.keyboardLayoutOf(node.id).high, 96);
  });

  test('the default range clears the decoration, and a repeat is a no-op', () {
    final node = add(Obj.gKslider);
    final standard = controller.keyboardLayoutOf(node.id);
    controller.setKeyboardRange(node.id, standard);
    expect(controller.undoScope.canUndo, isFalse);

    controller.setKeyboardRange(node.id, standard.movedHigh(1)!);
    controller.setKeyboardRange(node.id, standard);
    expect(gui(node, PatchGuiProperty.keyLow), '');
    expect(gui(node, PatchGuiProperty.keyHigh), '');
  });

  test('the velocity switches between depth and a fixed value, held to '
      '1–127, undoably', () {
    final node = add(Obj.gKslider);
    expect(controller.keyboardVelocityOf(node.id), isNull);

    controller.setKeyboardVelocity(node.id, 100);
    controller.setKeyboardVelocity(node.id, 300);
    expect(gui(node, PatchGuiProperty.keyVelocity), '127');
    expect(controller.keyboardVelocityOf(node.id), 127);

    controller.setKeyboardVelocity(node.id, null);
    expect(gui(node, PatchGuiProperty.keyVelocity), '');
    controller.undoScope.undo();
    controller.undoScope.undo();
    expect(controller.keyboardVelocityOf(node.id), 100);
  });

  test('anything but a keyboard is left alone', () {
    final node = add(Obj.gSlider);
    controller.setKeyboardRange(node.id, KeyboardLayout(60, 72));
    controller.setKeyboardVelocity(node.id, 64);
    expect(controller.undoScope.canUndo, isFalse);
    expect(gui(node, PatchGuiProperty.keyLow), '');
  });

  test('a reloaded keyboard is as wide as the range it saved', () {
    final registered = NodeTypeRegistry.instance.find(Obj.gKslider)!;
    final size = registered.sizeForGui!({
      PatchGuiProperty.keyLow: '0',
      PatchGuiProperty.keyHigh: '127',
    });
    expect(size.width, registered.defaultSize!.width * 75 / 22);
    expect(registered.sizeForGui!(const {}), registered.defaultSize);
  });
}
