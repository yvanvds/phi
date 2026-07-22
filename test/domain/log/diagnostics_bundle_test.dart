import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/diagnostics_bundle.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';

/// The report bundle's assembly (design `docs/design/diagnostics.md` §6, issue
/// #272): pure Dart, so "complete and stable-ordered" is proven here against
/// plain fakes — no engine, no clipboard, no disk.
void main() {
  LogEntry entry(String text, {LogSource source = LogSource.app}) => LogEntry(
    source: source,
    level: LogLevel.info,
    time: DateTime(2026, 7, 22, 14, 33, 55, 123),
    text: text,
  );

  DiagnosticsBundle bundle({
    double sampleRate = 48000,
    int bufferSize = 512,
    double outputLatencyMs = 10.7,
    String layout = 'stereo',
    String? projectPath = r'C:\projects\set.phi',
    List<LogEntry> log = const [],
    int logLineLimit = DiagnosticsBundle.defaultLogLineLimit,
  }) => DiagnosticsBundle(
    appVersion: '0.1.0',
    engineVersion: 'yse-test 9.9.1',
    libraryPath: r'C:\engine\yse\bin',
    device: 'Alpha · WASAPI',
    sampleRate: sampleRate,
    bufferSize: bufferSize,
    outputLatencyMs: outputLatencyMs,
    layout: layout,
    droppedCallbacks: 3,
    projectPath: projectPath,
    log: log,
    logLineLimit: logLineLimit,
  );

  test('renders every section, complete', () {
    final report = bundle(
      log: [entry('device opened', source: LogSource.engine)],
    ).render();

    expect(report, contains('Phi diagnostics'));
    expect(report, contains('App version: 0.1.0'));
    expect(report, contains('libYSE version: yse-test 9.9.1'));
    expect(report, contains(r'YSE_DLL_PATH: C:\engine\yse\bin'));
    expect(report, contains('Active device: Alpha · WASAPI'));
    expect(
      report,
      contains(
        'Active state: 48000 Hz · 512 frames · 10.7 ms latency · stereo',
      ),
    );
    expect(report, contains('Dropped callbacks: 3'));
    expect(report, contains(r'Open project: C:\projects\set.phi'));
    expect(report, contains('Log (last 1 lines):'));
    expect(report, contains('device opened'));
  });

  test('keeps a stable section order so reports diff cleanly', () {
    final report = bundle().render();
    final lines = report.split('\n');

    // The fixed order: header → versions → paths → audio → project → log.
    expect(lines[0], 'Phi diagnostics');
    expect(lines[1], startsWith('App version:'));
    expect(lines[2], startsWith('libYSE version:'));
    expect(lines[3], startsWith('YSE_DLL_PATH:'));
    expect(lines[4], startsWith('Active device:'));
    expect(lines[5], startsWith('Active state:'));
    expect(lines[6], startsWith('Dropped callbacks:'));
    expect(lines[7], startsWith('Open project:'));
    expect(lines[8], startsWith('Log (last'));

    // Two composes of identical inputs are byte-identical (the diff contract).
    expect(bundle().render(), report);
  });

  test('tails the log to the last N lines', () {
    final log = [for (var i = 0; i < 250; i++) entry('line $i')];
    final report = bundle(log: log, logLineLimit: 200).render();

    expect(report, contains('Log (last 200 lines):'));
    // The oldest 50 fell off; the newest survived.
    expect(report, isNot(contains('line 49')));
    expect(report, contains('line 50'));
    expect(report, contains('line 249'));
  });

  test('an empty log reads as a plain note, not a blank block', () {
    final report = bundle(log: const []).render();
    expect(report, contains('Log (last 0 lines):'));
    expect(report, contains('(no log entries)'));
  });

  test('no open device collapses the audio state to a plain note', () {
    final report = bundle(
      sampleRate: 0,
      bufferSize: 0,
      outputLatencyMs: 0,
    ).render();
    expect(report, contains('Active state: no device open'));
    expect(report, isNot(contains('Hz')));
  });

  test('a null project path reads as no project open', () {
    final report = bundle(projectPath: null).render();
    expect(report, contains('Open project: (no project open)'));
  });
}
