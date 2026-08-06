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
const _beta = AudioDeviceDescriptor(
  name: 'Beta',
  hostName: 'ASIO',
  sampleRates: [48000.0],
  bufferSizes: [128],
  defaultBufferSize: 128,
);

void main() {
  late FakeYseGateway gateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway()
      // Both interfaces are in the machine when the engine starts, so both are
      // in the enumeration the engine takes there and keeps (issue #412) — that
      // is what lets `loseEveryDevice` below drive the loss it describes, where
      // Beta *resolves* and then refuses to open.
      ..devices = const [_alpha, _beta]
      ..engineVersionValue = 'yse-test 9.9.1'
      ..libraryPathValue = r'C:\engine\yse\bin';
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
    void Function()? afterStart,
  }) async {
    // Started inside the test body, so the telemetry timer lives in the same
    // fake-async zone [tick] drives (a timer created in `setUp` is real).
    engine.start();
    // A sustained stall — past the 3-tick floor for Alpha's 256 frames @
    // 48 kHz, so one telemetry tick latches a single stall event.
    //
    // Seeded *after* start, because `initShared()` zeroes
    // `currentlyMissedCallbacks` (issue #402): the engine cannot boot into a
    // stall, so a fake that let one be seeded before `init()` was describing a
    // machine the app never meets.
    gateway.deviceStallTicksValue = 8;
    engine.switchAudioDevice(
      const AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
    );
    afterStart?.call();
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

  /// Drives a total device loss the way the coordinator meets one: the chosen
  /// target refuses to open — the engine having already closed Alpha to try it —
  /// and Alpha is gone by the time the revert goes looking for it. The engine
  /// ends up on nothing, and `activeAudioSettings` reads `null` (issue #408).
  void loseEveryDevice() {
    gateway.unopenableDeviceNames.add('Beta');
    // Alpha is pulled out of the machine. Its cached entry stays — the engine
    // never rescans (issue #412) — so the revert still *resolves* Alpha and it
    // is the open that fails, which is exactly the production shape.
    gateway.devices = const [_beta];
    engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Beta'),
    );
  }

  testWidgets('after a total loss the device row names no device', (
    tester,
  ) async {
    await pumpSection(tester, afterStart: loseEveryDevice);

    // The row a performer reads when their audio has just vanished must not
    // name the interface the engine is no longer on (issue #408).
    expect(engine.activeAudioSettings, isNull);
    expect(find.text('ACTIVE DEVICE'), findsOneWidget);
    expect(find.textContaining('none — no audio device open'), findsOneWidget);
    expect(find.textContaining('Alpha'), findsNothing);
    expect(find.textContaining('WASAPI'), findsNothing);

    // …and the block they paste says the same thing.
    final copied = await captureCopy(tester);
    expect(copied, contains('Active device: none — no audio device open'));
    expect(copied, isNot(contains('Alpha')));
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
