import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/button/primary_button.dart';
import 'package:phi/design/widgets/meter/peak_meter.dart';
import 'package:phi/engine/engine.dart';

import '../test/engine/test_doubles/fake_yse_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hello world: tap play sine, engine arms, meter responds', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );

    await tester.pumpWidget(PhiApp(engine: engine));
    await tester.pumpAndSettle();

    expect(find.byType(PrimaryButton), findsOneWidget);
    expect(find.byType(PeakMeter), findsOneWidget);
    expect(find.text('PLAY SINE'), findsOneWidget);

    gateway.cpuLoadValue = 0.0;
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(gateway.audioTestOn, isTrue);
    expect(find.text('STOP SINE'), findsOneWidget);

    gateway.cpuLoadValue = 0.6;
    await tester.pump(const Duration(milliseconds: 40));

    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(gateway.audioTestOn, isFalse);
    expect(find.text('PLAY SINE'), findsOneWidget);

    await engine.dispose();
  });
}
