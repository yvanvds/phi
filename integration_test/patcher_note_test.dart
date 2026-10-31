import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/tokens/phi_note_swatch.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_metrics.dart';
import 'package:phi/domain/patcher/patch_gui_property.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_type_name.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/library/patch_entity_strip.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **multi-line, resizable note** (issue #488) through
/// the real [PhiApp] — real rail navigation, focus tree, fonts and layout —
/// backed by a [FakePatcherGateway] so no native `libyse` is touched.
///
/// The legs, in one session: a note is typed through the inline object box
/// with a `# ` heading and a Shift+Enter line break while Enter still commits;
/// the paragraph wraps at the default reading width and the box on screen is
/// the box the controller measured (real fonts, which is where a widget test's
/// Ahem sizing would lie); a drag on its right edge widens it and re-wraps it,
/// and Ctrl+Z / Ctrl+Y walk that one step; and the note survives a dump →
/// parse round trip — the duplicated patch opens with the same text, breaks
/// and width.
///
/// Issue #511 rides the same session: the selected note is coloured from the
/// reference panel's swatch row, repaints in the swatch's dark-theme field
/// (the app's theme) with the heading in its ink, undoes and redoes as one
/// step, and the reloaded copy comes back with the same colour.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  const textDesc = PatchObjectDescriptor(
    type: Obj.gText,
    description: 'text label',
    category: PatchObjectCategory.gui,
    isDsp: false,
    inlets: [],
    outlets: [],
    params: [
      PatchParamDescriptor(
        name: 'text',
        doc: 'label text',
        defaultValue: '',
        range: 'any string',
      ),
    ],
  );

  const paragraph =
      'A sine runs into the dac. Drag the slider to sweep its frequency and '
      'listen to how the pitch follows; then swap the sine for a saw.';

  testWidgets('patcher: a note wraps, takes line breaks, resizes from its '
      'edge with one undo step, takes a colour, and survives a reload', (
    tester,
  ) async {
    final gateway = FakePatcherGateway()
      ..objectTypesCatalogue = [
        ...FakePatcherGateway.defaultCatalogue,
        textDesc,
      ];
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
    // Empty grid below the seeded slider → sine → dac chain.
    const scenePoint = Offset(220, 380);
    final at = canvasRect.topLeft + scenePoint;
    expect(canvasRect.contains(at), isTrue);

    Finder field() => find.byKey(PatchInlineObjectBox.fieldKey);
    String fieldText() => tester.widget<TextField>(field()).controller!.text;

    Future<void> chord(LogicalKeyboardKey mod, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(mod);
      await tester.pumpAndSettle();
    }

    // ── 1) type a note: heading, Shift+Enter break, paragraph, Enter ────────
    await tester.tapAt(at);
    await tester.pump();
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(field(), findsOneWidget);

    await tester.enterText(field(), 'text # Tutorial');
    await tester.pumpAndSettle();
    await chord(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.enter);
    expect(field(), findsOneWidget, reason: 'Shift+Enter must not commit');
    expect(fieldText(), 'text # Tutorial\n');

    await tester.enterText(field(), '${fieldText()}$paragraph');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(field(), findsNothing, reason: 'Enter commits the note');

    PatchNode noteIn(Iterable<PatchNode> nodes) =>
        nodes.singleWhere((n) => PatchTypeName.isNote(n.type));
    final note = noteIn(patcher.graph.nodes);
    expect(patcher.argsOf(note.id), '# Tutorial\n$paragraph');

    // ── 2) it wraps at the reading width, heading on top ─────────────────────
    expect(note.size.width, PatchNoteMetrics.defaultWidth);
    final noteBox = find.byType(PatchNoteBox);
    expect(noteBox, findsOneWidget);
    // Real fonts: the box on screen is exactly the box the model measured.
    expect(tester.getSize(noteBox), note.size);
    expect(find.text('Tutorial\n$paragraph'), findsOneWidget);
    final oneLine = PatchNoteMetrics.sizeFor(display: 'x').height;
    expect(note.size.height, greaterThan(oneLine * 3));

    // ── 3) drag the right edge: wider, shorter, one undo step ────────────────
    final narrow = note.size;
    final edge =
        canvasRect.topLeft +
        Offset(
          note.position.dx + note.size.width - 1,
          note.position.dy + note.size.height / 2,
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

    expect(note.size.width, narrow.width + 120);
    expect(note.size.height, lessThan(narrow.height));
    expect(tester.getSize(noteBox), note.size);
    expect(patcher.noteWidthOf(note.id), narrow.width + 120);

    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(note.size, narrow);
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY);
    expect(note.size.width, narrow.width + 120);
    final resized = note.size;

    // ── 3b) colour it from the reference panel (issue #511) ─────────────────
    BoxDecoration paperOf(Finder box) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(of: box, matching: find.byType(DecoratedBox))
                      .first,
                )
                .decoration
            as BoxDecoration;
    Color? inkOf(String shown) =>
        tester.widget<Text>(find.text(shown)).textSpan!.style!.color;
    const shown = 'Tutorial\n$paragraph';
    const swatch = PhiNoteSwatch.cyan;

    expect(paperOf(noteBox).color, PhiColors.noteBg, reason: 'no bg = plain');
    await tester.tapAt(
      canvasRect.topLeft + note.position + note.size.center(Offset.zero),
    );
    await tester.pumpAndSettle();
    final chip = find.byKey(PatchReferencePanel.noteColorKey(swatch.name));
    expect(chip, findsOneWidget, reason: 'a selected note shows the swatches');
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(patcher.noteColorOf(note.id), swatch.name);
    expect(paperOf(noteBox).color, swatch.bgDark);
    expect(paperOf(noteBox).border!.top.color, swatch.lineDark);
    expect(inkOf(shown), swatch.fgDark);
    final heading =
        (tester.widget<Text>(find.text(shown)).textSpan! as TextSpan)
                .children!
                .first
            as TextSpan;
    expect(heading.style!.color, swatch.fgDark);
    expect(note.size, resized, reason: 'a colour does not move the box');

    // No click back on the canvas: the pick hands the keyboard back, so the
    // very next Ctrl+Z undoes it.
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(patcher.noteColorOf(note.id), '');
    expect(paperOf(noteBox).color, PhiColors.noteBg);
    expect(note.size, resized, reason: 'the undo took the colour, not width');
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY);
    expect(paperOf(noteBox).color, swatch.bgDark);

    // ── 4) save → reload: the duplicated patch is parsed from the dump ───────
    final first = library.openAddress!;
    await tester.tap(find.byKey(PatchEntityStrip.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchEntityStrip.menuKey(first)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('duplicate'));
    await tester.pumpAndSettle();
    expect(library.openAddress, isNot(first));

    final copyEditor = library.openEditor!;
    final copy = noteIn(copyEditor.graph.nodes);
    expect(copyEditor.argsOf(copy.id), '# Tutorial\n$paragraph');
    expect(
      copyEditor.guiPropertyOf(copy.id, PatchGuiProperty.width),
      '${(narrow.width + 120).round()}',
    );
    expect(copy.size, resized);
    expect(tester.getSize(find.byType(PatchNoteBox)), resized);
    expect(
      copyEditor.guiPropertyOf(copy.id, PatchGuiProperty.background),
      swatch.name,
    );
    expect(paperOf(find.byType(PatchNoteBox)).color, swatch.bgDark);

    session.dispose();
    await engine.dispose();
  });
}
