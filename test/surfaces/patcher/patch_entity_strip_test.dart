import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/patch_bus_option.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/surfaces/patcher/library/patch_entity_strip.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget coverage for the patcher **entity strip** (issue #224): every strip
/// affordance — open on tap, and the add / row menus for new patch · new group ·
/// duplicate · rename · delete — driven through the [PatchLibraryController].
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  late FakePatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late PatchLibraryController controller;

  PatchLibraryController buildController() => PatchLibraryController(
    registry: registry,
    patches: reconciler,
    gateway: gateway,
    busOptions: () => const <PatchBusOption>[],
  );

  setUp(() {
    gateway = FakePatcherGateway();
    registry = ProjectRegistry();
    reconciler = PatchReconciler(
      gateway: gateway,
      resolveBus: (_) => null,
      onNotice: (_) {},
    );
  });

  tearDown(() {
    controller.dispose();
    registry.dispose();
  });

  Future<void> pumpStrip(WidgetTester tester) async {
    controller = buildController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PatchEntityStrip(
              controller: controller,
              initiallyExpanded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a row per patch and opens one on tap', (tester) async {
    registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
    registry.createEntity(patch('b'), payload: PatchPayload.empty.toJson());
    await pumpStrip(tester);

    expect(find.byKey(PatchEntityStrip.rowKey(patch('a'))), findsOneWidget);
    expect(find.byKey(PatchEntityStrip.rowKey(patch('b'))), findsOneWidget);

    await tester.tap(find.byKey(PatchEntityStrip.rowKey(patch('b'))));
    await tester.pumpAndSettle();

    expect(controller.openAddress, patch('b'));
  });

  testWidgets('the add menu creates a new patch', (tester) async {
    await pumpStrip(tester);
    expect(controller.isEmpty, isTrue);

    await tester.tap(find.byKey(PatchEntityStrip.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new patch'));
    await tester.pumpAndSettle();

    expect(controller.isEmpty, isFalse);
    expect(controller.openAddress, isNotNull);
  });

  testWidgets('the add menu creates a new group', (tester) async {
    await pumpStrip(tester);

    await tester.tap(find.byKey(PatchEntityStrip.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new group'));
    await tester.pumpAndSettle();

    expect(
      registry
          .childrenOfKind(RegistryKinds.patch)
          .where((n) => n.name == 'group'),
      hasLength(1),
    );
  });

  testWidgets('the row menu duplicates a patch', (tester) async {
    registry.createEntity(
      patch('src'),
      payload: const PatchPayload(dump: {'objects': 1}).toJson(),
    );
    await pumpStrip(tester);

    await tester.tap(find.byKey(PatchEntityStrip.menuKey(patch('src'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('duplicate'));
    await tester.pumpAndSettle();

    expect(
      registry.contains(patch('src_copy')),
      isTrue,
      reason: 'the copy sits beside the original',
    );
  });

  testWidgets('the row menu renames a patch', (tester) async {
    registry.createEntity(patch('old'), payload: PatchPayload.empty.toJson());
    await pumpStrip(tester);

    await tester.tap(find.byKey(PatchEntityStrip.menuKey(patch('old'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.tap(find.widgetWithText(TextButton, 'rename'));
    await tester.pumpAndSettle();

    expect(registry.contains(patch('old')), isFalse);
    expect(registry.contains(patch('renamed')), isTrue);
  });

  testWidgets('the row menu deletes a patch behind a confirm', (tester) async {
    registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
    registry.createEntity(patch('b'), payload: PatchPayload.empty.toJson());
    await pumpStrip(tester);

    await tester.tap(find.byKey(PatchEntityStrip.menuKey(patch('a'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
    // Confirm dialog → its 'delete' action.
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(registry.contains(patch('a')), isFalse);
    expect(registry.contains(patch('b')), isTrue);
  });

  testWidgets('collapsed by default, toggles open', (tester) async {
    controller = buildController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PatchEntityStrip(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed: the add button is not shown until expanded.
    expect(find.byKey(PatchEntityStrip.addMenuKey), findsNothing);
    await tester.tap(find.byKey(PatchEntityStrip.expandToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(PatchEntityStrip.addMenuKey), findsOneWidget);
  });
}
