import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/diagnostics_report.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [48000.0],
  bufferSizes: [256],
  defaultBufferSize: 256,
);

/// The shell reporter that gathers live diagnostics facts into the bundle (design
/// §6, issue #272): drives the real engine façade (over the fake gateway) plus a
/// shared log store, so `compose` is proven to read the right sources.
void main() {
  late FakeYseGateway gateway;
  late PhiEngine engine;
  late LogStore log;

  setUp(() {
    gateway = FakeYseGateway()
      ..devices = const [_alpha]
      ..engineVersionValue = 'yse-test 9.9.1'
      ..libraryPathValue = r'C:\engine\yse\bin'
      // A sustained stall: well past the 3-tick floor for Alpha's 256 frames
      // @ 48 kHz, so the first telemetry tick latches one stall event.
      ..deviceStallTicksValue = 7;
    engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 5),
    );
    engine.start();
    engine.switchAudioDevice(
      const AudioSettings(
        outputHost: 'WASAPI',
        outputDevice: 'Alpha',
        layout: SpeakerLayout.stereo,
      ),
    );
    log = LogStore();
  });

  tearDown(() async {
    log.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  void seed(String text, {LogSource source = LogSource.app}) => log.add(
    LogEntry(
      source: source,
      level: LogLevel.info,
      time: DateTime(2026, 7, 22, 14, 33, 55, 123),
      text: text,
    ),
  );

  test(
    'composes the full bundle from the live engine, log, and project',
    () async {
      seed('audio device opened', source: LogSource.engine);
      seed('project saved');
      // The stall counters accumulate on the telemetry tick, so let one land
      // before composing (issue #350).
      await engine.telemetry.first.timeout(const Duration(seconds: 1));

      final report = DiagnosticsReport(
        engine: engine,
        log: log,
        projectPath: () => r'C:\projects\set.phi',
        appVersion: '0.1.0',
      ).compose();

      expect(report, contains('Phi diagnostics'));
      expect(report, contains('App version: 0.1.0'));
      expect(report, contains('libYSE version: yse-test 9.9.1'));
      expect(report, contains(r'YSE_DLL_PATH: C:\engine\yse\bin'));
      expect(report, contains('Active device: Alpha · WASAPI'));
      // Live audio read-back: rate/buffer/latency/layout off activeAudioState.
      expect(report, contains('48000 Hz · 256 frames'));
      expect(report, contains('stereo'));
      // One latched stall event, with the raw gauge's worst run beside it — not
      // the raw gauge itself (issue #350).
      expect(
        report,
        contains(
          'Audio stalls: 1 (worst run 7 control ticks with no callback)',
        ),
      );
      expect(report, contains(r'Open project: C:\projects\set.phi'));
      expect(report, contains('audio device opened'));
      expect(report, contains('project saved'));
    },
  );

  test('an unset library path reads as the bundled-library note', () {
    gateway.libraryPathValue = null;
    final report = DiagnosticsReport(engine: engine, log: log).compose();
    expect(report, contains('YSE_DLL_PATH: (not set — bundled library)'));
  });

  test('a null project resolver reads as no project open', () {
    final report = DiagnosticsReport(engine: engine, log: log).compose();
    expect(report, contains('Open project: (no project open)'));
  });
}
