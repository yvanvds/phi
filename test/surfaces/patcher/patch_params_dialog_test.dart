import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/params/patch_params_dialog.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget test for the metadata-driven params dialog (issue #223): it seeds one
/// field per documented creation parameter from the node's current arguments,
/// and applying it round-trips a fake type's parameters through `setParams`,
/// undoable in one step.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;
  late PatchObjectDescriptor sineDesc;

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
    // The fake catalogue's `~sine` carries one param, `frequency` (default 440).
    sineDesc = gateway.objectTypes().firstWhere((d) => d.type == Obj.dSine);
  });

  tearDown(() => controller.dispose());

  int handle() => gateway.nodes.keys.single;

  Future<void> openDialog(WidgetTester tester, PatchNode node) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showPatchParamsDialog(
                ctx,
                controller: controller,
                node: node,
                descriptor: sineDesc,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('seeds the field from the object default and applies via '
      'setParams; undo/redo round-trips', (tester) async {
    // Drag-create seeds `~sine` with its documented default args ("440").
    final node = controller.addObject(desc: sineDesc, position: Offset.zero);
    expect(controller.argsOf(node.id), '440');

    await openDialog(tester, node);

    // The field is seeded from the node's current argument string.
    final field = find.byKey(PatchParamsDialog.fieldKey('frequency'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '440');

    // Edit it and apply.
    await tester.enterText(field, '880');
    await tester.tap(find.byKey(PatchParamsDialog.doneKey));
    await tester.pumpAndSettle();

    // The change reached the gateway (setParams) and the tracked args.
    expect(controller.argsOf(node.id), '880');
    expect(gateway.nodes[handle()]!.args, '880');
    expect(gateway.calls, contains('setParams:${handle()}:880'));

    // One undo restores the whole parameter set...
    controller.undo();
    expect(controller.argsOf(node.id), '440');
    expect(gateway.nodes[handle()]!.args, '440');

    // ...and redo re-applies it.
    controller.redo();
    expect(controller.argsOf(node.id), '880');
    expect(gateway.nodes[handle()]!.args, '880');
  });

  testWidgets('applying without an edit records no undo step', (tester) async {
    final node = controller.addObject(desc: sineDesc, position: Offset.zero);
    await openDialog(tester, node);

    await tester.tap(find.byKey(PatchParamsDialog.doneKey));
    await tester.pumpAndSettle();

    // Nothing changed → the undo stack stays empty, so an undo is a no-op.
    expect(controller.undoScope.canUndo, isFalse);
    expect(controller.argsOf(node.id), '440');
  });
}
