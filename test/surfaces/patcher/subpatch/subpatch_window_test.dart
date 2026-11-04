import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:phi/surfaces/patcher/subpatch/subpatch_window_view.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../../engine/test_doubles/fake_yse_gateway.dart';

/// The subpatch window (issue #481): a subpatch box opens in a window of its
/// own — a second view, here through the test binding's windowing owner —
/// whose canvas shows the box's contents and edits the same graph.
void main() {
  late FakeYseGateway gateway;
  late FakePatcherGateway patcherGateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    patcherGateway = FakePatcherGateway();
    engine = PhiEngine(
      gateway,
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 50),
    );
    NodeTypeRegistry.instance.clear();
    engine.start();
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
    NodeTypeRegistry.instance.clear();
  });

  PatchObjectDescriptor desc(String type) =>
      patcherGateway.objectTypes().firstWhere((d) => d.type == type);

  PatchNodeId make(String type, {String args = '', PatchNodeId? inside}) =>
      engine.patcher.createObject(
        desc: desc(type),
        position: const Offset(80, 80),
        args: args,
        container: inside,
      )!;

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PatcherSurface(engine: engine)),
      ),
    );
    await tester.pump();
  }

  Finder inWindow(Finder f) =>
      find.descendant(of: find.byType(SubpatchWindowView), matching: f);

  Finder mainCanvas() =>
      find.byWidgetPredicate((w) => w is PatcherCanvas && w.scope == null);

  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final g = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
      view: tester.viewOf(target),
    );
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<void> openFromMenu(WidgetTester tester, PatchNodeId box) async {
    await rightClick(
      tester,
      find.descendant(
        of: mainCanvas(),
        matching: find.byKey(PatcherNodeView.objectLineKey(box)),
      ),
    );
    await tester.tap(find.byKey(PatcherSurface.openSubpatchItemKey));
    await tester.pumpAndSettle();
  }

  testWidgets('a window not sized yet draws nothing and overflows nothing, '
      'then shows the subpatch', (tester) async {
    final box = make(Obj.patcher, args: 'gain');
    Widget sized(double size) => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: size,
          child: SubpatchWindowView(
            editor: engine.patcher,
            box: box,
            objectTypes: const [],
          ),
        ),
      ),
    );

    // Linux lays a new native window out at 1x1 first (#557).
    await tester.pumpWidget(sized(1));
    expect(tester.takeException(), isNull);
    expect(find.byKey(SubpatchWindowView.canvasKey), findsNothing);

    await tester.pumpWidget(sized(400));
    expect(tester.takeException(), isNull);
    expect(find.byKey(SubpatchWindowView.canvasKey), findsOneWidget);
  });

  testWidgets('the node menu opens a subpatch in a window of its own, showing '
      'only what is inside it', (tester) async {
    await pumpSurface(tester);
    final box = make(Obj.patcher, args: 'gain');
    final inner = make(Obj.dSine, args: '440', inside: box);
    await tester.pump();

    // Inside objects are not drawn on the main canvas.
    expect(
      find.descendant(of: mainCanvas(), matching: find.byType(PatcherNodeView)),
      findsOneWidget,
    );

    await openFromMenu(tester, box);

    expect(tester.binding.platformDispatcher.views, hasLength(2));
    expect(find.byType(SubpatchWindowView), findsOneWidget);
    expect(inWindow(find.byKey(SubpatchWindowView.titleKey)), findsOneWidget);
    expect(inWindow(find.text('gain')), findsOneWidget);
    expect(
      inWindow(find.byKey(PatcherNodeView.objectLineKey(inner))),
      findsOneWidget,
    );
    expect(inWindow(find.byType(PatcherNodeView)), findsOneWidget);
  });

  testWidgets('opening the same subpatch twice keeps one window', (
    tester,
  ) async {
    await pumpSurface(tester);
    final box = make(Obj.patcher, args: 'gain');
    await tester.pump();

    await openFromMenu(tester, box);
    await openFromMenu(tester, box);

    expect(find.byType(SubpatchWindowView), findsOneWidget);
    expect(tester.binding.platformDispatcher.views, hasLength(2));
  });

  testWidgets('a boundary object made in the window gives the box a pin, and '
      'the reference panel counts it', (tester) async {
    await pumpSurface(tester);
    final box = make(Obj.patcher, args: 'gain');
    await tester.pump();
    await openFromMenu(tester, box);

    final boxNode = engine.patcher.graph.nodeById(box)!;
    expect(boxNode.inputs, isEmpty);
    final inlet = make(Obj.dInlet, args: '0', inside: box);
    make(Obj.gOutlet, args: '0', inside: box);
    await tester.pumpAndSettle();

    expect(boxNode.inputs, hasLength(1));
    expect(boxNode.outputs, hasLength(1));
    // The inlet object's parent-facing pin is not drawn inside: one dot, its
    // outlet, rather than two.
    final inletBox = tester.widget<PatchObjectBox>(
      find.descendant(
        of: inWindow(
          find.byWidgetPredicate(
            (w) => w is PatcherNodeView && w.node.id == inlet,
          ),
        ),
        matching: find.byType(PatchObjectBox),
      ),
    );
    expect(inletBox.inputPortXs, isEmpty);
    expect(inletBox.outputPortXs, hasLength(1));

    // Select the box in the main window: the panel names it and counts pins.
    await tester.tap(
      find.descendant(
        of: mainCanvas(),
        matching: find.byKey(PatcherNodeView.objectLineKey(box)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(PatchReferencePanel.subpatchNameKey)).data,
      '= gain',
    );
    expect(
      tester
          .widget<Text>(find.byKey(PatchReferencePanel.subpatchInletsKey))
          .data,
      '= 1',
    );
    expect(
      tester
          .widget<Text>(find.byKey(PatchReferencePanel.subpatchOutletsKey))
          .data,
      '= 1',
    );
  });

  testWidgets('deleting the box closes its window; so does leaving the patch', (
    tester,
  ) async {
    await pumpSurface(tester);
    final box = make(Obj.patcher, args: 'gain');
    await tester.pump();
    await openFromMenu(tester, box);
    expect(find.byType(SubpatchWindowView), findsOneWidget);

    engine.patcher
      ..selectNodes({box})
      ..deleteSelection();
    await tester.pumpAndSettle();
    expect(find.byType(SubpatchWindowView), findsNothing);
    expect(tester.binding.platformDispatcher.views, hasLength(1));

    engine.patcher.undo();
    await tester.pumpAndSettle();
    await openFromMenu(tester, box);
    expect(find.byType(SubpatchWindowView), findsOneWidget);

    // A different patch opens: the subpatch's patch is no longer on screen.
    final library = engine.patchLibrary;
    library.newPatch();
    await tester.pumpAndSettle();
    expect(find.byType(SubpatchWindowView), findsNothing);
  });

  testWidgets('in run mode a double-click on the box opens it', (tester) async {
    await pumpSurface(tester);
    final box = make(Obj.patcher, args: 'gain');
    await tester.pump();
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();

    final line = find.descendant(
      of: mainCanvas(),
      matching: find.byKey(PatcherNodeView.objectLineKey(box)),
    );
    await tester.tap(line);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(line);
    await tester.pumpAndSettle();

    expect(find.byType(SubpatchWindowView), findsOneWidget);
    // The window plays in the surface's mode.
    expect(
      tester.widget<PatcherCanvas>(inWindow(find.byType(PatcherCanvas))).mode,
      PatchCanvasMode.run,
    );
  });

  group('abstractions (issue #553)', () {
    /// A definition `patch.gain` holding a `~inlet 0` and a `~sine`, and a box
    /// of it in the open patch.
    ({PatchNodeId box, PatcherController definition}) anInstance() {
      final library = engine.patchLibrary;
      final open = library.openAddress!;
      final address = library.newPatch()!;
      library.rename(address, 'gain');
      final gain = EntityAddress.parse('patch.gain');
      final definition = library.editorFor(gain)!;
      definition.createObject(
        desc: desc(Obj.dInlet),
        position: const Offset(40, 40),
        args: '0',
      );
      definition.createObject(
        desc: desc(Obj.dSine),
        position: const Offset(40, 120),
        args: '220',
      );
      library.open(open);
      return (
        box: make(Obj.patcher, args: 'patch.gain'),
        definition: definition,
      );
    }

    Finder line(PatchNodeId box) => find.descendant(
      of: mainCanvas(),
      matching: find.byKey(PatcherNodeView.objectLineKey(box)),
    );

    testWidgets(
      'typing a patch\'s address into the object box makes an instance',
      (tester) async {
        final made = anInstance();
        await pumpSurface(tester);
        final parent = engine.patcher;
        final before = parent.nodesIn(null).length;

        final at = tester.getTopLeft(mainCanvas()) + const Offset(60, 300);
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(PatchInlineObjectBox.fieldKey),
          'patch.gain',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(parent.nodesIn(null), hasLength(before + 1));
        final box = parent.nodesIn(null).last;
        expect(box.id, isNot(made.box));
        expect(box.type, Obj.patcher);
        expect(parent.argsOf(box.id), 'patch.gain');
        expect(parent.nodesIn(box.id), hasLength(2));
        expect(box.inputs, hasLength(1));
      },
    );

    testWidgets('open definition edits the patch, and the instance follows', (
      tester,
    ) async {
      final made = anInstance();
      await pumpSurface(tester);

      await rightClick(tester, line(made.box));
      await tester.tap(find.byKey(PatcherSurface.openDefinitionItemKey));
      await tester.pumpAndSettle();

      final view = tester.widget<SubpatchWindowView>(
        find.byType(SubpatchWindowView),
      );
      expect(identical(view.editor, made.definition), isTrue);
      expect(view.box, isNull);
      expect(
        tester
            .widget<Text>(inWindow(find.byKey(SubpatchWindowView.titleKey)))
            .data,
        'patch.gain',
      );
      expect(
        inWindow(find.byType(PatcherNodeView)),
        findsNWidgets(2),
        reason: 'what the definition holds',
      );

      // Made in the window: on the definition, and from there on the instance.
      view.onCreateObject!(desc(Obj.dOutlet), const Offset(40, 200), args: '0');
      await tester.pumpAndSettle();

      expect(made.definition.nodesIn(null), hasLength(3));
      final parent = engine.patcher;
      expect(parent.nodesIn(made.box), hasLength(3));
      expect(parent.graph.nodeById(made.box)!.outputs, hasLength(1));

      // Opening it again focuses the one window.
      await rightClick(tester, line(made.box));
      await tester.tap(find.byKey(PatcherSurface.openDefinitionItemKey));
      await tester.pumpAndSettle();
      expect(find.byType(SubpatchWindowView), findsOneWidget);
    });

    testWidgets('an instance opened by itself is played, not edited', (
      tester,
    ) async {
      final made = anInstance();
      await pumpSurface(tester);

      await rightClick(tester, line(made.box));
      expect(find.text('open instance'), findsOneWidget);
      await tester.tap(find.byKey(PatcherSurface.openSubpatchItemKey));
      await tester.pumpAndSettle();

      final view = tester.widget<SubpatchWindowView>(
        find.byType(SubpatchWindowView),
      );
      expect(identical(view.editor, engine.patcher), isTrue);
      expect(view.box, made.box);
      expect(view.mode, PatchCanvasMode.run);
      expect(view.onToggleMode, isNull);
      expect(view.onCreateObject, isNull);
      expect(view.onNodeContextMenu, isNull);
      expect(inWindow(find.byKey(SubpatchWindowView.modeKey)), findsNothing);
      expect(inWindow(find.byType(PatcherNodeView)), findsNWidgets(2));
    });

    testWidgets('detach makes it an ordinary subpatch that stays as it is', (
      tester,
    ) async {
      final made = anInstance();
      await pumpSurface(tester);

      await rightClick(tester, line(made.box));
      await tester.tap(find.byKey(PatcherSurface.detachItemKey));
      await tester.pumpAndSettle();

      final parent = engine.patcher;
      expect(parent.abstractionOf(made.box), isNull);
      expect(parent.subpatchNameOf(made.box), 'gain');
      expect(parent.nodesIn(made.box), hasLength(2));

      await rightClick(tester, line(made.box));
      expect(find.text('open subpatch'), findsOneWidget);
      expect(find.byKey(PatcherSurface.makeAbstractionItemKey), findsOneWidget);
      expect(find.byKey(PatcherSurface.openDefinitionItemKey), findsNothing);
    });

    testWidgets(
      'make abstraction turns a box into an instance of a new patch',
      (tester) async {
        final box = make(Obj.patcher, args: 'level');
        make(Obj.dSine, args: '220', inside: box);
        await pumpSurface(tester);

        await rightClick(tester, line(box));
        await tester.tap(find.byKey(PatcherSurface.makeAbstractionItemKey));
        await tester.pumpAndSettle();

        final level = EntityAddress.parse('patch.level');
        expect(engine.patcher.abstractionOf(box), level);
        expect(
          engine.patchLibrary.editorFor(level)!.nodesIn(null),
          hasLength(1),
        );
        expect(
          engine.patchLibrary.openAddress,
          isNot(level),
          reason: 'stays put',
        );
      },
    );

    testWidgets(
      'the reference panel names the definition and offers the verbs',
      (tester) async {
        final made = anInstance();
        await pumpSurface(tester);

        await tester.tap(line(made.box));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Text>(
                find.byKey(PatchReferencePanel.subpatchDefinitionKey),
              )
              .data,
          '= patch.gain',
        );
        expect(
          tester
              .widget<Text>(find.byKey(PatchReferencePanel.subpatchInstanceKey))
              .data,
          '= #${engine.patcher.instanceNumberOf(made.box)}',
        );
        expect(find.byKey(PatchReferencePanel.detachKey), findsOneWidget);
        expect(
          find.byKey(PatchReferencePanel.makeAbstractionKey),
          findsNothing,
        );

        await tester.tap(find.byKey(PatchReferencePanel.openSubpatchKey));
        await tester.pumpAndSettle();
        final view = tester.widget<SubpatchWindowView>(
          find.byType(SubpatchWindowView),
        );
        expect(identical(view.editor, made.definition), isTrue);
      },
    );

    testWidgets('a definition\'s window closes when its patch is renamed', (
      tester,
    ) async {
      final made = anInstance();
      await pumpSurface(tester);

      await rightClick(tester, line(made.box));
      await tester.tap(find.byKey(PatcherSurface.openDefinitionItemKey));
      await tester.pumpAndSettle();
      expect(find.byType(SubpatchWindowView), findsOneWidget);

      engine.patchLibrary.rename(EntityAddress.parse('patch.gain'), 'level');
      await tester.pumpAndSettle();

      expect(find.byType(SubpatchWindowView), findsNothing);
      expect(
        engine.patcher.abstractionOf(made.box),
        EntityAddress.parse('patch.level'),
      );
    });

    testWidgets('the palette offers the patches the open one can use', (
      tester,
    ) async {
      anInstance();
      await pumpSurface(tester);

      expect(find.byKey(PatcherPalette.entryKey('patch.gain')), findsOneWidget);
      final open = engine.patchLibrary.openAddress!;
      expect(find.byKey(PatcherPalette.entryKey(open.format())), findsNothing);
    });

    testWidgets('the canvas says when a definition costs the parent a cable', (
      tester,
    ) async {
      final made = anInstance();
      final parent = engine.patcher;
      final sine = make(Obj.dSine, args: '440');
      parent.connectViaGesture(
        PatchPortId(nodeId: sine, side: PatchPortSide.output, index: 0),
        PatchPortId(nodeId: made.box, side: PatchPortSide.input, index: 0),
      );
      await pumpSurface(tester);

      final pin = made.definition
          .nodesIn(null)
          .firstWhere((n) => n.type == Obj.dInlet);
      made.definition
        ..selectNodes({pin.id})
        ..deleteSelection();
      await tester.pump();

      expect(find.byKey(PatcherCanvas.patchNoticeKey), findsOneWidget);
      expect(find.textContaining('1 CABLE DROPPED'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });
}
