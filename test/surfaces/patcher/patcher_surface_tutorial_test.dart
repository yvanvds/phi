import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/tutorial/patch_tutorial.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/tutorial/memory_patch_tutorial_source.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette_tab.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_browser.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// The patcher surface's **tutorial** wiring (issue #489): the reference
/// panel's "Open tutorial" appears only for a type that has one, the palette's
/// Tutorials browser opens one too, and an open tutorial is read-only — run
/// mode only, no way into edit mode, no drop target, a banner instead of the
/// placement bar — until it is closed.
void main() {
  // A `~sine` tutorial in the fake gateway's dump format.
  const tutorial = PatchTutorial(
    title: 'sine — a tone',
    covers: [Obj.dSine],
    payload: PatchPayload(
      dump: {
        'objects': [
          {'id': 0, 'type': Obj.gSlider, 'args': '', 'x': 40, 'y': 40},
          {'id': 1, 'type': Obj.dSine, 'args': '440', 'x': 40, 'y': 140},
        ],
        'cables': [
          {'from': 0, 'outlet': 0, 'to': 1, 'inlet': 0},
        ],
      },
    ),
  );

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
      patchTutorialSource: MemoryPatchTutorialSource({
        TutorialCatalog.indexPath: jsonEncode({Obj.dSine: 'sine'}),
        TutorialCatalog.assetPathFor('sine'): jsonEncode(tutorial.toJson()),
      }),
    );
    NodeTypeRegistry.instance.clear();
    engine.start();
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
    NodeTypeRegistry.instance.clear();
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PatcherSurface(engine: engine)),
      ),
    );
    await tester.pumpAndSettle();
  }

  PatchCanvasMode canvasMode(WidgetTester tester) =>
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode;

  testWidgets('"Open tutorial" shows only for a type that has a tutorial', (
    tester,
  ) async {
    await pumpSurface(tester);

    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dDac)));
    await tester.pump();
    expect(find.byKey(PatchReferencePanel.openTutorialKey), findsNothing);

    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dSine)));
    await tester.pump();
    expect(find.byKey(PatchReferencePanel.openTutorialKey), findsOneWidget);
  });

  testWidgets('an open tutorial is read-only until it is closed', (
    tester,
  ) async {
    await pumpSurface(tester);
    final projectEditor = engine.patcher;

    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dSine)));
    await tester.pump();
    await tester.tap(find.byKey(PatchReferencePanel.openTutorialKey));
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    expect(library.tutorial, isNotNull);
    expect(engine.patcher, isNot(same(projectEditor)));
    expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);
    expect(
      find.text(PatchTutorialBar.bannerText.toUpperCase()),
      findsOneWidget,
    );
    expect(find.text('sine — a tone'), findsOneWidget);
    expect(find.byType(PatchPlacementBar), findsNothing);

    // Run mode only: the demo controls are playable, nothing else.
    expect(canvasMode(tester), PatchCanvasMode.run);
    expect(
      find.byType(DragTarget<PatchObjectDescriptor>),
      findsNothing,
      reason: 'no palette drop creates into a tutorial',
    );

    // Ctrl+E, the way into edit mode, is refused.
    await tester.tapAt(tester.getCenter(find.byType(PatcherCanvas)));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(canvasMode(tester), PatchCanvasMode.run);
    expect(
      library.tutorial!.editor.graph.nodes,
      hasLength(2),
      reason: 'the graph is untouched',
    );

    await tester.tap(find.byKey(PatchTutorialBar.closeKey));
    await tester.pumpAndSettle();
    expect(library.tutorial, isNull);
    expect(engine.patcher, same(projectEditor));
    expect(find.byType(PatchPlacementBar), findsOneWidget);
    expect(canvasMode(tester), PatchCanvasMode.edit);
  });

  testWidgets('the Tutorials browser lists and opens tutorials, and the '
      'browser request switches the palette to it', (tester) async {
    await pumpSurface(tester);

    expect(find.byType(PatchTutorialBrowser), findsNothing);
    engine.patchLibrary.requestTutorialBrowser();
    await tester.pumpAndSettle();
    expect(find.byType(PatchTutorialBrowser), findsOneWidget);
    expect(
      find.byKey(PatchTutorialBrowser.entryKey(Obj.dSine)),
      findsOneWidget,
    );
    expect(find.byKey(PatchTutorialBrowser.entryKey(Obj.dDac)), findsNothing);

    // Search narrows it.
    await tester.enterText(find.byKey(PatchTutorialBrowser.searchKey), 'zzz');
    await tester.pump();
    expect(find.byKey(PatchTutorialBrowser.emptyKey), findsOneWidget);
    await tester.enterText(find.byKey(PatchTutorialBrowser.searchKey), 'sin');
    await tester.pump();

    await tester.tap(find.byKey(PatchTutorialBrowser.entryKey(Obj.dSine)));
    await tester.pumpAndSettle();
    expect(engine.patchLibrary.tutorial?.slug, 'sine');

    // Back to the objects tab.
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.objects)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(PatcherPalette.searchKey), findsOneWidget);
  });

  testWidgets('copy to project leaves the tutorial for an editable patch', (
    tester,
  ) async {
    await pumpSurface(tester);
    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dSine)));
    await tester.pump();
    await tester.tap(find.byKey(PatchReferencePanel.openTutorialKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(PatchTutorialBar.copyKey));
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    expect(library.tutorial, isNull);
    expect(library.openAddress?.format(), 'patch.tutorials.sine');
    expect(find.byType(PatchPlacementBar), findsOneWidget);
    expect(canvasMode(tester), PatchCanvasMode.edit);
    expect(engine.patcher.graph.nodes, hasLength(2));
  });
}
