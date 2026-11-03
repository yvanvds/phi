import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
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
}
