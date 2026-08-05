import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of **colour instead of glyphs** (issue #380, design §5 +
/// §12.4) through the real [PhiApp] — real rail navigation, real palette, real
/// canvas layout, **real fonts** — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched.
///
/// The `~` / `.` prefix stops being drawn and the text colour says what it said:
/// DSP in [PhiColors.cool] (the blue the cables and the overview already carry),
/// control in the ordinary foreground. The prefixed id stays canonical — it is
/// what the node holds, what the gateway is called with, and what the reference
/// panel shows you in order to type it.
///
/// A widget test structurally cannot stand in for this. The rule is a *system*
/// one: the same fact has to read identically on a canvas box, a palette row and
/// a completion row that three different files build, the canvas box's width is
/// measured from the line it prints (so a prefix dropped in one place and not
/// the other mis-sizes the box in the real font), and the ambiguity refusal only
/// matters inside the composed app, where the keys have to survive the canvas's
/// own shortcuts to reach the inline box at all.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The two objects that collide once the prefix is not drawn — both read `*`,
  /// and only colour tells them apart. The engine has four such pairs.
  const controlMultiply = PatchObjectDescriptor(
    type: Obj.gMultiply,
    description: 'multiply a number',
    category: PatchObjectCategory.math,
    isDsp: false,
    inlets: [],
    outlets: [],
    params: [],
  );
  const dspMultiply = PatchObjectDescriptor(
    type: Obj.dMultiply,
    description: 'multiply a signal',
    category: PatchObjectCategory.math,
    isDsp: true,
    inlets: [],
    outlets: [],
    params: [],
  );

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: the ~ / . prefix is gone from the screen and colour '
      'carries it — on the canvas, in the palette, and while typing', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway()
      ..objectTypesCatalogue = [
        ...FakePatcherGateway.defaultCatalogue,
        controlMultiply,
        dspMultiply,
      ];
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface, which seeds slider → sine → dac.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final patcher = engine.patcher;

    Color lineColorOf(String type) {
      final node = patcher.graph.nodes.firstWhere((n) => n.type == type);
      return tester
          .widget<Text>(find.byKey(PatcherNodeView.objectLineKey(node.id)))
          .style!
          .color!;
    }

    // ─── (1) the canvas reads bare, in the DSP blue ───────────────────────
    Finder onCanvas(String line) => find.descendant(
      of: find.byType(PatcherCanvas),
      matching: find.text(line),
    );

    expect(onCanvas('sine 440'), findsOneWidget);
    expect(onCanvas('dac'), findsOneWidget);
    expect(lineColorOf(Obj.dSine), PhiColors.cool);
    expect(lineColorOf(Obj.dDac), PhiColors.cool);
    // The nodes still *are* `~sine` and `~dac`: only the drawing changed.
    expect(patcher.graph.nodes.any((n) => n.type == Obj.dSine), isTrue);
    expect(
      find.descendant(
        of: find.byType(PatcherCanvas),
        matching: find.textContaining('~'),
      ),
      findsNothing,
    );

    // ─── (2) the palette reads bare too, and lost its DSP dot ─────────────
    Text paletteName(String type) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(PatcherPalette.entryKey(type)),
        matching: find.byType(Text),
      ),
    );

    expect(paletteName(Obj.dSine).data, 'sine');
    expect(paletteName(Obj.gSlider).data, 'slider');
    expect(paletteName(Obj.dSine).style!.color, PhiColors.cool);
    expect(paletteName(Obj.gSlider).style!.color, PhiColors.fg1);
    // The two `*`s sit side by side, told apart by colour alone.
    expect(paletteName(Obj.dMultiply).data, '*');
    expect(paletteName(Obj.gMultiply).data, '*');
    expect(paletteName(Obj.dMultiply).style!.color, PhiColors.cool);
    expect(paletteName(Obj.gMultiply).style!.color, PhiColors.fg1);
    expect(
      find.descendant(
        of: find.byType(PatcherPalette),
        matching: find.textContaining('~'),
      ),
      findsNothing,
    );

    // ─── (3) the reference panel keeps the canonical id ───────────────────
    // It is the reference: this is where the exact name to type is looked up.
    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dSine)));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PatchReferencePanel),
        matching: find.text(Obj.dSine),
      ),
      findsOneWidget,
    );

    // ─── (4) typing: an ambiguous bare name is not resolved for you ───────
    final canvasRect = tester.getRect(find.byType(PatcherCanvas));
    Future<void> doubleClickAt(Offset scenePoint) async {
      final at = canvasRect.topLeft + scenePoint;
      expect(canvasRect.contains(at), isTrue);
      await tester.tapAt(at);
      await tester.pump();
      await tester.tapAt(at);
      await tester.pumpAndSettle();
    }

    Future<void> type(String text) async {
      await tester.enterText(find.byKey(PatchInlineObjectBox.fieldKey), text);
      await tester.pumpAndSettle();
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    final seeded = patcher.graph.nodes.length;
    await doubleClickAt(const Offset(220, 380));
    await type('*');
    await press(LogicalKeyboardKey.enter);

    // Nothing was created, and the list stayed up with both candidates in the
    // colours that separate them — the choice is visible rather than guessed.
    expect(patcher.graph.nodes, hasLength(seeded));
    expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);
    expect(
      find.text('pick one · ${Obj.gMultiply} or ${Obj.dMultiply}'),
      findsOneWidget,
    );

    Text completionName(String type) => tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(PatchInlineObjectBox.rowKey(type)),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(completionName(Obj.dMultiply).data, '*');
    expect(completionName(Obj.dMultiply).style!.color, PhiColors.cool);
    expect(completionName(Obj.gMultiply).style!.color, PhiColors.fg1);

    // One keystroke settles it: the arrow moves onto the DSP one, Enter takes
    // it, and what lands is the canonical `~*`.
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.enter);

    expect(patcher.graph.nodes, hasLength(seeded + 1));
    final made = patcher.graph.nodes.last;
    expect(made.type, Obj.dMultiply);
    // …and the gateway was asked for the canonical id, not the bare name.
    expect(
      patcherGateway.calls.any(
        (c) => c.startsWith('createObject:') && c.endsWith(':~*:'),
      ),
      isTrue,
    );
    expect(lineColorOf(Obj.dMultiply), PhiColors.cool);
    expect(
      tester
          .widget<Text>(find.byKey(PatcherNodeView.objectLineKey(made.id)))
          .data,
      '*',
    );

    // ─── (5) an unambiguous bare name still resolves straight through ─────
    await doubleClickAt(const Offset(420, 380));
    await type('sine 220');
    await press(LogicalKeyboardKey.enter);

    expect(patcher.graph.nodes, hasLength(seeded + 2));
    expect(patcher.graph.nodes.last.type, Obj.dSine);
    expect(onCanvas('sine 220'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
