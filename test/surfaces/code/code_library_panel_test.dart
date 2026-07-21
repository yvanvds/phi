import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/code_script.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/state/code_library_controller.dart';
import 'package:phi/surfaces/code/code_library_panel.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

Map<String, Object?> _payload([String source = '']) =>
    CodeScript(source: source).toJson();

void main() {
  late ProjectRegistry registry;
  late CodeLibraryController controller;

  CodeLibraryController build({void Function(ProjectRegistry)? seed}) {
    registry = ProjectRegistry();
    seed?.call(registry);
    controller = CodeLibraryController(registry: registry);
    addTearDown(() {
      controller.dispose();
      registry.dispose();
    });
    return controller;
  }

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 500,
              child: CodeLibraryPanel(
                controller: controller,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragOnto(
    WidgetTester tester,
    Finder source,
    Finder target,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  void seedTree(ProjectRegistry r) {
    r.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
    r.createEntity(_addr('code.utils.gain'), payload: _payload());
    r.createEntity(_addr('code.utils.env'), payload: _payload());
    r.createEntity(_addr('code.b'), payload: _payload('bbb\n'));
  }

  testWidgets('renders the code tree with groups and order', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);

    expect(find.text('a'), findsOneWidget);
    expect(find.text('utils'), findsOneWidget);
    expect(find.text('gain'), findsOneWidget);
    expect(find.text('env'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    double topOf(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(topOf('a'), lessThan(topOf('utils')));
    expect(topOf('utils'), lessThan(topOf('gain')));
    expect(topOf('gain'), lessThan(topOf('env')));
    expect(topOf('env'), lessThan(topOf('b')));
  });

  testWidgets('tapping a script opens it (open-swap)', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);
    // Construction auto-opened the first script (a).
    expect(controller.openAddress, _addr('code.a'));

    await tester.tap(find.byKey(CodeLibraryPanel.rowKey(_addr('code.b'))));
    await tester.pumpAndSettle();

    expect(controller.openAddress, _addr('code.b'));
    expect(controller.openSource, 'bbb\n');
  });

  testWidgets('the collapse toggle hides then shows the tree', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);
    expect(find.text('a'), findsOneWidget);

    await tester.tap(find.byKey(CodeLibraryPanel.expandToggleKey).first);
    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);

    await tester.tap(find.byKey(CodeLibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('empty namespace shows the hint', (tester) async {
    build();
    await pumpPanel(tester);
    expect(find.text('no scripts yet — use + to add one'), findsOneWidget);
  });

  group('context menu', () {
    testWidgets('new script adds a sibling script', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(CodeLibraryPanel.menuKey(_addr('code.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('new script'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('code.script')), isTrue);
    });

    testWidgets('new group adds a group folder', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(CodeLibraryPanel.menuKey(_addr('code.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('new group'));
      await tester.pumpAndSettle();

      expect(registry.groupAt(_addr('code.group')), isNotNull);
    });

    testWidgets('duplicate copies the script to <name>_copy', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(CodeLibraryPanel.menuKey(_addr('code.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('duplicate'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('code.a_copy')), isTrue);
    });

    testWidgets('rename moves the entity to the new slug', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(CodeLibraryPanel.menuKey(_addr('code.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rename…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'lead riff');
      await tester.tap(find.widgetWithText(TextButton, 'rename'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('code.a')), isFalse);
      expect(registry.contains(_addr('code.lead_riff')), isTrue);
    });

    testWidgets('delete confirms then removes the script', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(CodeLibraryPanel.menuKey(_addr('code.b'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'delete'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('code.b')), isFalse);
    });
  });

  testWidgets('dragging a script onto a group re-parents it', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);

    await dragOnto(
      tester,
      find.byKey(CodeLibraryPanel.dragHandleKey(_addr('code.a'))),
      find.byKey(CodeLibraryPanel.rowKey(_addr('code.utils'))),
    );

    expect(registry.contains(_addr('code.a')), isFalse);
    expect(registry.contains(_addr('code.utils.a')), isTrue);
  });
}
