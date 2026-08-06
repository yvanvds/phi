import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end drag-to-reorder through the real workstation (issue #427): two
/// built-ins are added from the `+` catalogue, then the first chip's handle is
/// dragged down past the second. `ReorderableListView.onReorderItem` reports
/// the chip's **final** (post-removal) index, and `chain.reorder` speaks that
/// same contract — a drop one past the last slot must land the chip *at* the
/// end, not one short (the classic off-by-one this test pins down against the
/// real shell, real fonts, and the engine's own shared chain).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: dragging a chip handle down past the last slot lands it '
      'at the end', (tester) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Navigate to the MIDI surface (the engine owns the shared chain).
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final chain = engine.midiOrNull!.chain;
    final startCount = chain.transforms.length;

    // Add two distinct built-ins; they append at the tail in pick order.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('transpose · +12 st'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('quantize · 1/16'));
    await tester.pumpAndSettle();

    expect(chain.transforms, hasLength(startCount + 2));
    expect(chain.transforms[startCount].label, 'transpose · +12 st');
    expect(chain.transforms[startCount + 1].label, 'quantize · 1/16');
    expect(find.byType(TransformChip), findsNWidgets(startCount + 2));

    // Drag the transpose chip's handle down well past the quantize chip (the
    // last row): the raw drop slot is one past the end, which `onReorderItem`
    // adjusts to the post-removal final index before calling `chain.reorder`.
    final handles = find.byIcon(Icons.drag_indicator);
    final rowExtent =
        tester.getCenter(handles.at(startCount + 1)).dy -
        tester.getCenter(handles.at(startCount)).dy;
    await tester.drag(handles.at(startCount), Offset(0, rowExtent * 4));
    await tester.pumpAndSettle();

    expect(chain.transforms, hasLength(startCount + 2));
    expect(chain.transforms[startCount].label, 'quantize · 1/16');
    expect(chain.transforms[startCount + 1].label, 'transpose · +12 st');

    session.dispose();
    await engine.dispose();
  });
}
