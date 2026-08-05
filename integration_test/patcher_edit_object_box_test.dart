import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that an object's parameters are **visible on the canvas**
/// (issue #356) and **editable on the object itself** (issue #382), through the
/// real [PhiApp] — real rail navigation, real palette drag, real double-click
/// timing, real fonts and layout — backed by a [FakePatcherGateway] so no
/// native `libyse.dll` is touched.
///
/// Widget tests cover each piece in isolation and structurally cannot cover
/// this: the object box only reprints because the *composed* canvas rebuilds the
/// node from its own listener, the reference panel only refreshes because the
/// surface binds it to the live graph, and the in-place editor is a real text
/// field opened out of the canvas's raw pointer pipeline — which is exactly
/// where a competing gesture recogniser, or the canvas taking the keyboard back
/// on the release that opened the box, would show up.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A control object with a documented parameter and **no hand-authored body**
  /// — the case the default args body exists for. Every type in the fake
  /// catalogue has a registered node descriptor, so one has to be added.
  const metro = PatchObjectDescriptor(
    type: '.metro',
    description: 'metronome',
    category: PatchObjectCategory.time,
    isDsp: false,
    inlets: [
      PatchInletDescriptor(
        label: 'on',
        doc: 'start / stop',
        range: '',
        accepts: {PatchInletAccept.integer, PatchInletAccept.bang},
      ),
    ],
    outlets: [
      PatchOutletDescriptor(
        label: 'out',
        doc: 'tick',
        range: '',
        type: PatchOutletType.bang,
      ),
    ],
    params: [
      PatchParamDescriptor(
        name: 'interval',
        doc: 'milliseconds between ticks',
        defaultValue: '250',
        range: '1..60000',
      ),
    ],
  );

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  /// What the node actually prints on the canvas — its object box's one line
  /// (issue #379), which is the whole node now.
  Finder bodyText(String value) => find.descendant(
    of: find.byType(PatchObjectBox),
    matching: find.text(value),
  );

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('a dropped object shows its args, a double-click retypes them in '
      'place, and the canvas + reference panel follow the edit and its undo', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway()
      ..objectTypesCatalogue = [...FakePatcherGateway.defaultCatalogue, metro];
    patcherGateway.topologyOverrides['.metro'] = const PatcherNodeSnapshot(
      inputs: 1,
      outputs: 1,
      inputKinds: [PatchPortKind.control],
      outputKinds: [PatchPortKind.control],
    );
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // ─── (1) drag-create: the node arrives printing what it is ────────────
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(PatcherPalette.entryKey('.metro'))),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(PatcherCanvas)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Seeded with the documented default and saying so — this used to be an
    // empty box that told the user nothing at all.
    expect(bodyText('metro 250'), findsOneWidget);

    // ─── (2) double-click the box — it becomes the editor ─────────────────
    // On the box itself: there is no header left to aim at (issue #379), and no
    // dialog left to open (issue #382). Two quick taps, read out of the
    // canvas's own pointer timing.
    final at = tester.getCenter(bodyText('metro 250'));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    expect(find.byKey(PatcherCanvas.inlineEditKey), findsOneWidget);
    final field = find.byKey(PatchInlineObjectBox.fieldKey);
    // Seeded with the line the object was printing a moment ago, and holding
    // the keyboard: the canvas took focus on the very release that opened it,
    // so this is where a focus fight would show.
    expect(tester.widget<TextField>(field).controller!.text, 'metro 250');
    expect(tester.widget<TextField>(field).focusNode!.hasPrimaryFocus, isTrue);

    // ─── (3) the selection alone already answered "set to what?" ──────────
    // The first click selected the node, so the panel is showing its value
    // beside the box being typed into — which is why the dialog's own copy of
    // that documentation had nothing left to do.
    expect(
      find.byKey(PatchReferencePanel.valueKey('interval')),
      findsOneWidget,
    );
    expect(find.text('= 250'), findsOneWidget);

    // An argument the type documents a range for is refused before it can reach
    // the engine, and the box stays open on the typo.
    await tester.enterText(field, 'metro 99999');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);
    expect(bodyText('metro 250'), findsOneWidget);

    await tester.enterText(field, 'metro 500');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // ─── (4) canvas and panel both follow the apply, immediately ──────────
    expect(find.byKey(PatcherCanvas.inlineEditKey), findsNothing);
    expect(bodyText('metro 500'), findsOneWidget);
    expect(bodyText('metro 250'), findsNothing);
    expect(find.text('= 500'), findsOneWidget);

    // ─── (5) …and both round-trip under Ctrl+Z / Ctrl+Y ───────────────────
    // One step for the whole edit, and the keyboard is already back on the
    // canvas to press it.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(bodyText('metro 250'), findsOneWidget);
    expect(find.text('= 250'), findsOneWidget);

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(bodyText('metro 500'), findsOneWidget);
    expect(find.text('= 500'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
