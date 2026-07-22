import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/settings/diagnostics_settings_section.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [48000.0],
  bufferSizes: [256],
  defaultBufferSize: 256,
);

void main() {
  late FakeYseGateway gateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway()
      ..devices = const [_alpha]
      ..engineVersionValue = 'yse-test 9.9.1'
      ..libraryPathValue = r'C:\engine\yse\bin'
      ..missedCallbacksValue = 3;
    engine = PhiEngine(gateway, telemetryInterval: const Duration(days: 1));
    engine.start(
      audioSettings: const AudioSettings(
        outputHost: 'WASAPI',
        outputDevice: 'Alpha',
      ),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    String Function()? report,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosticsSettingsSection(engine: engine, report: report),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String?> captureCopy(WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('copy for bug report'));
    await tester.pumpAndSettle();
    return copied;
  }

  testWidgets('renders the read-only diagnostic facts', (tester) async {
    await pumpSection(tester);

    expect(find.text('LIBYSE VERSION'), findsOneWidget);
    expect(find.textContaining('yse-test 9.9.1'), findsOneWidget);
    expect(find.text('YSE_DLL_PATH'), findsOneWidget);
    expect(find.textContaining(r'C:\engine\yse\bin'), findsOneWidget);
    expect(find.text('ACTIVE DEVICE'), findsOneWidget);
    expect(find.textContaining('Alpha'), findsOneWidget);
    expect(find.textContaining('WASAPI'), findsOneWidget);
    // The drop counter reflects the gateway's live value.
    expect(find.textContaining('3'), findsWidgets);
  });

  testWidgets('an unset library path reads as bundled', (tester) async {
    gateway.libraryPathValue = null;
    await pumpSection(tester);

    expect(find.textContaining('bundled library'), findsOneWidget);
  });

  testWidgets('the copy button yields a paste-ready block', (tester) async {
    await pumpSection(tester);
    final copied = await captureCopy(tester);

    // The confirmation shows and the clipboard holds the read-only block.
    expect(find.text('copied'), findsOneWidget);
    expect(copied, isNotNull);
    expect(copied, contains('Phi diagnostics'));
    expect(copied, contains('libYSE version: yse-test 9.9.1'));
    expect(copied, contains(r'YSE_DLL_PATH: C:\engine\yse\bin'));
    expect(copied, contains('Active device: Alpha · WASAPI'));
    expect(copied, contains('Dropped callbacks: 3'));
  });

  testWidgets('a supplied report builder copies the full bundle instead', (
    tester,
  ) async {
    // Production wires `report` to `DiagnosticsReport.compose` (issue #272); the
    // button then copies whatever it yields, not the read-only rows.
    await pumpSection(
      tester,
      report: () => 'FULL BUNDLE\nLog (last 200 lines):',
    );
    final copied = await captureCopy(tester);

    expect(find.text('copied'), findsOneWidget);
    expect(copied, 'FULL BUNDLE\nLog (last 200 lines):');
  });
}
