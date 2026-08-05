import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that an object can be **retyped in place** (issue #383),
/// through the real [PhiApp] — real rail navigation, real double-click timing,
/// real fonts and layout — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched.
///
/// Widget tests cover the pieces in isolation and structurally cannot cover
/// this: a retype replaces the node in the graph, so what the canvas draws, what
/// the cable layer paints and what the reference panel documents all have to
/// re-resolve against an object that was not there a frame ago — through the
/// surface's own listeners, in the composed app, with the keyboard where the
/// gesture left it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A second oscillator to retype the seeded `~sine` into: same shape, so
  /// every cable in the patch survives the change.
  const saw = PatchObjectDescriptor(
    type: '~saw',
    description: 'sawtooth oscillator',
    category: PatchObjectCategory.oscillator,
    isDsp: true,
    inlets: [
      PatchInletDescriptor(
        label: 'freq',
        doc: 'frequency in Hz',
        range: '0..20000',
        accepts: {PatchInletAccept.buffer, PatchInletAccept.float},
      ),
    ],
    outlets: [
      PatchOutletDescriptor(
        label: 'out',
        doc: 'signal',
        range: '',
        type: PatchOutletType.buffer,
      ),
    ],
    params: [
      PatchParamDescriptor(
        name: 'frequency',
        doc: 'initial frequency',
        defaultValue: '440',
        range: '0..20000',
      ),
    ],
  );

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  /// What a node actually prints on the canvas — its object box's one line
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

  testWidgets('retyping an object in place keeps its place and the cables that '
      'still land, says what it could not carry, and undoes whole', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway()
      ..objectTypesCatalogue = [...FakePatcherGateway.defaultCatalogue, saw];
    patcherGateway.topologyOverrides['~saw'] = const PatcherNodeSnapshot(
      inputs: 1,
      outputs: 1,
      inputKinds: [PatchPortKind.control],
      outputKinds: [PatchPortKind.audio],
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

    // The seed lays down slider → sine → dac: three nodes, two cables, and one
    // object box printing what it is.
    final graph = engine.patcher.graph;
    expect(graph.cables, hasLength(2));
    expect(bodyText('sine 440'), findsOneWidget);
    final sineId = graph.nodes.firstWhere((n) => n.type == Obj.dSine).id;
    PatchNode node() => graph.nodeById(sineId)!;
    final where = node().position;

    // ─── (1) double-click the box and type a different name ───────────────
    final at = tester.getCenter(bodyText('sine 440'));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    expect(find.byKey(PatcherCanvas.inlineEditKey), findsOneWidget);
    final field = find.byKey(PatchInlineObjectBox.fieldKey);
    expect(tester.widget<TextField>(field).controller!.text, 'sine 440');
    // The panel is already documenting the object being typed into.
    expect(find.text('= 440'), findsOneWidget);

    await tester.enterText(field, 'saw 300');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // ─── (2) a different object, in the same place, still wired ───────────
    expect(find.byKey(PatcherCanvas.inlineEditKey), findsNothing);
    expect(bodyText('saw 300'), findsOneWidget);
    expect(bodyText('sine 440'), findsNothing);
    expect(node().type, '~saw');
    expect(node().position, where);
    expect(graph.selectedNodes, {sineId});
    // Both cables still land on the new object, so both were carried over —
    // this is the whole difference between a retype and a delete-and-create.
    expect(graph.cables, hasLength(2));
    expect(patcherGateway.cables, hasLength(2));
    // Nothing was lost, so the canvas says nothing.
    expect(find.byKey(PatcherCanvas.retypeNoticeKey), findsNothing);
    // …and the reference panel is documenting the object that is there now.
    expect(
      find.byKey(PatchReferencePanel.valueKey('frequency')),
      findsOneWidget,
    );
    expect(find.text('= 300'), findsOneWidget);

    // ─── (3) one Ctrl+Z puts the old object back, cables and all ──────────
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(bodyText('sine 440'), findsOneWidget);
    expect(graph.nodeById(sineId)!.type, Obj.dSine);
    expect(graph.cables, hasLength(2));

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(bodyText('saw 300'), findsOneWidget);
    expect(graph.cables, hasLength(2));

    // ─── (4) a retype with nowhere for the cables to land says so ─────────
    final onSaw = tester.getCenter(bodyText('saw 300'));
    await tester.tapAt(onSaw);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(onSaw);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'slider');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // A `.slider` has no inlet at all and emits a float: the cable arriving
    // from the other slider has nowhere to land, and the one leaving for the
    // dac is no longer a signal the dac accepts. Both go — and the canvas names
    // them, because a connection that quietly vanished is discovered an hour
    // later, on a patch that has gone silent for no visible reason.
    expect(graph.nodeById(sineId)!.type, Obj.gSlider);
    expect(graph.cables, isEmpty);
    expect(find.byKey(PatcherCanvas.retypeNoticeKey), findsOneWidget);
    expect(find.text('RETYPED · 2 CABLES DROPPED'), findsOneWidget);

    // ─── (5) …and that undoes whole too — the cables come back with it ────
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(graph.nodeById(sineId)!.type, '~saw');
    expect(bodyText('saw 300'), findsOneWidget);
    expect(graph.cables, hasLength(2));
    expect(patcherGateway.cables, hasLength(2));

    session.dispose();
    await engine.dispose();
  });
}
