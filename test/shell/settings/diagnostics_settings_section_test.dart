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
      // A sustained stall — past the 3-tick floor for Alpha's 256 frames @
      // 48 kHz, so one telemetry tick latches a single stall event.
      ..deviceStallTicksValue = 8;
    // A far-future telemetry interval keeps `pumpAndSettle` from spinning on the
    // rebuild; [tick] fires exactly one telemetry emission when a test wants it.
    engine = PhiEngine(gateway, telemetryInterval: const Duration(days: 1));
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    String Function()? report,
  }) async {
    // Started inside the test body, so the telemetry timer lives in the same
    // fake-async zone [tick] drives (a timer created in `setUp` is real).
    engine.start();
    engine.switchAudioDevice(
      const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosticsSettingsSection(engine: engine, report: report),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fires exactly one telemetry emission (the interval is a day out) and lets
  /// the section rebuild off it.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(days: 1));
    await tester.pump();
  }

  /// Cancels the telemetry timer before the widget-tree invariant check, which
  /// runs at the end of the test body — ahead of the `tearDown` disposal.
  void stopEngine() => engine.stop();

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
    // Before any telemetry tick nothing has been sampled yet, so the counter
    // reads zero rather than echoing the engine's raw gauge (issue #350).
    expect(find.text('AUDIO STALLS'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    // One tick over a sustained gauge latches exactly one stall event.
    await tick(tester);
    expect(find.text('1'), findsOneWidget);
    stopEngine();
  });

  testWidgets('an unset library path reads as bundled', (tester) async {
    gateway.libraryPathValue = null;
    await pumpSection(tester);

    expect(find.textContaining('bundled library'), findsOneWidget);
    stopEngine();
  });

  testWidgets('the copy button yields a paste-ready block', (tester) async {
    await pumpSection(tester);
    await tick(tester);
    final copied = await captureCopy(tester);

    // The confirmation shows and the clipboard holds the read-only block.
    expect(find.text('copied'), findsOneWidget);
    expect(copied, isNotNull);
    expect(copied, contains('Phi diagnostics'));
    expect(copied, contains('libYSE version: yse-test 9.9.1'));
    expect(copied, contains(r'YSE_DLL_PATH: C:\engine\yse\bin'));
    expect(copied, contains('Active device: Alpha · WASAPI'));
    expect(copied, contains('Audio stalls: 1'));
    stopEngine();
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
    stopEngine();
  });
}
