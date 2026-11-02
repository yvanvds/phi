import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/domain/patcher/patch_gui_property.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/library/patch_entity_strip.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that a `.l` list box **can be widened** (issue #533)
/// through the real [PhiApp] — real rail navigation, fonts and layout — backed
/// by a [FakePatcherGateway].
///
/// A list longer than the default box is cut off with an ellipsis in the real
/// font; a drag on the box's right edge widens it until the whole list shows,
/// Ctrl+Z / Ctrl+Y walk that one step, and the width survives a dump → parse
/// round trip (the duplicated patch opens with the same wide box).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  const longList = 'note 60 100 ctl 61 100';

  testWidgets('patcher: a list box cut off at its default width widens from '
      'its right edge with one undo step and keeps the width on reload', (
    tester,
  ) async {
    final gateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    final patcher = engine.patcher;
    final canvasRect = tester.getRect(find.byType(PatcherCanvas));

    Future<void> chord(LogicalKeyboardKey mod, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(mod);
      await tester.pumpAndSettle();
    }

    // The list text on the canvas, once the live-value poll has come due.
    Future<RenderParagraph> shown() async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final text = find.descendant(
        of: find.byType(PatchListBox),
        matching: find.text(longList),
      );
      expect(text, findsOneWidget);
      return tester.renderObject<RenderParagraph>(text);
    }

    // ── 1) a `.l` at its default width cuts a long list off ──────────────────
    final d = NodeTypeRegistry.instance.find(Obj.gList)!;
    final list = patcher.addNode(
      desc: NodeDescriptor(
        type: d.type,
        defaultSize: d.defaultSize,
        sizeForGui: d.sizeForGui,
        defaultArgs: '',
        inputs: d.inputs,
        outputs: d.outputs,
        buildBody: d.buildBody,
        readsGuiValue: d.readsGuiValue,
      ),
      position: const Offset(220, 380),
    );
    await tester.pumpAndSettle();
    expect(list.size.width, PatchListBox.defaultWidth);
    expect(patcher.listBoxWidthOf(list.id), isNull);
    final handle = gateway.nodes.keys.single;
    gateway.sendList(patcher.instanceId, handle, 0, longList);
    expect(
      (await shown()).didExceedMaxLines,
      isTrue,
      reason: 'the default box is too narrow for "$longList"',
    );

    // ── 2) drag the right edge: the whole list shows, one undo step ─────────
    final narrow = list.size;
    final edge =
        canvasRect.topLeft +
        Offset(
          list.position.dx + list.size.width - 1,
          list.position.dy + list.size.height / 2,
        );
    final mouse = await tester.startGesture(
      edge,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await mouse.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await mouse.up();
    await tester.pumpAndSettle();

    final wide = narrow.width + 120;
    expect(list.size, Size(wide, narrow.height));
    expect(list.position, const Offset(220, 380), reason: 'resized, not moved');
    expect(tester.getSize(find.byType(PatchListBox)), list.size);
    expect(patcher.listBoxWidthOf(list.id), wide);
    expect(
      (await shown()).didExceedMaxLines,
      isFalse,
      reason: '"$longList" fits the widened box',
    );

    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(list.size, narrow);
    expect(patcher.listBoxWidthOf(list.id), isNull);
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY);
    expect(list.size.width, wide);

    // ── 3) save → reload: the duplicated patch is parsed from the dump ───────
    final first = library.openAddress!;
    await tester.tap(find.byKey(PatchEntityStrip.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchEntityStrip.menuKey(first)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('duplicate'));
    await tester.pumpAndSettle();
    expect(library.openAddress, isNot(first));

    final copyEditor = library.openEditor!;
    final PatchNode copy = copyEditor.graph.nodes.single;
    expect(
      copyEditor.guiPropertyOf(copy.id, PatchGuiProperty.width),
      '${wide.round()}',
    );
    expect(copy.size.width, wide);
    expect(tester.getSize(find.byType(PatchListBox)).width, wide);
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });
}
