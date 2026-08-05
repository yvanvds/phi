import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/params/patch_params_dialog.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the live GUI bodies + params dialog (issue #223) through
/// the real [PhiApp] — real rail navigation, layout, and fonts — backed by a
/// [FakePatcherGateway] so no native `libyse.dll` is touched.
///
/// Two user-visible flows: operating the seeded slider body writes through the
/// gateway (`sendFloat`), and double-clicking the non-GUI `~sine` node opens the
/// metadata params dialog whose apply round-trips through `setParams` into the
/// live patcher.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('operate a slider body and edit sine params via double-click', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway();
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

    // 1) Operate the seeded slider (a live GUI body) — its value reaches the
    //    gateway as a sendFloat.
    tester.widget<PhiFader>(find.byType(PhiFader)).onChanged(0.3);
    await tester.pump();
    expect(
      patcherGateway.calls.where((c) => c.startsWith('sendFloat')),
      isNotEmpty,
    );

    // 2) Double-click the `~sine` object box — one line reading `~sine 440`
    //    since issue #379, and the only thing left to aim at — to open the
    //    params dialog. Detected from raw pointer timing, so two quick taps
    //    suffice.
    final sineLine = find.text('~sine 440');
    expect(sineLine, findsOneWidget);
    final at = tester.getCenter(sineLine);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    // The dialog seeds the field from the sine's documented default frequency.
    final field = find.byKey(PatchParamsDialog.fieldKey('frequency'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '440');

    // Edit and apply → the change round-trips through setParams into the patch.
    await tester.enterText(field, '660');
    await tester.tap(find.byKey(PatchParamsDialog.doneKey));
    await tester.pumpAndSettle();

    final sine = engine.patcher.graph.nodes.firstWhere(
      (n) => n.type == Obj.dSine,
    );
    expect(engine.patcher.argsOf(sine.id), '660');
    expect(
      patcherGateway.calls.where((c) => c.startsWith('setParams')),
      isNotEmpty,
    );

    session.dispose();
    await engine.dispose();
  });
}
