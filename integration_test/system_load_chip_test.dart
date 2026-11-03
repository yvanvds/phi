import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/platform/thread_cpu/host_thread_cpu_sampler.dart';
import 'package:phi/platform/thread_cpu/thread_cpu_sampler.dart';
import 'package:phi/platform/thread_cpu/thread_cpu_snapshot.dart';
import 'package:phi/shell/bottom_status/system_load_chip.dart';
import 'package:phi/shell/bottom_status/system_load_popover.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/platform/thread_cpu/test_doubles/scripted_thread_cpu_sampler.dart';

/// Counts the snapshots a real sampler takes, so the test can wait for a
/// complete measuring window without guessing at timer latency.
class _CountingSampler implements ThreadCpuSampler {
  _CountingSampler(this._inner);

  final ThreadCpuSampler _inner;
  int samples = 0;

  @override
  int get logicalCores => _inner.logicalCores;

  @override
  ThreadCpuSnapshot sample() {
    samples++;
    return _inner.sample();
  }
}

/// End-to-end proof of the status bar's `SYS` chip (issue #24), driven through
/// the real [PhiApp] at a performance window size with real fonts: the
/// once-a-second monitor, the per-thread tracker, the dot beside `CPU`, and the
/// popover that opens upward out of the bottom strip.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeYseGateway gateway;
  late PhiEngine engine;
  late SessionState session;
  late AppSettingsController settings;
  late ProjectController controller;

  Future<void> boot(WidgetTester tester, ThreadCpuSampler sampler) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    gateway = FakeYseGateway();
    engine = PhiEngine(gateway);
    session = SessionState();
    settings = AppSettingsController(FakeAppSettingsStore(const AppSettings()));
    controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => FakeProjectStore(),
      journalStoreFactory: (_) => FakeJournalStore(),
      autosaveIntervalOverride: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
        threadCpuSampler: sampler,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    // Unmount first so the monitor's timer stops before the engine goes.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  }

  /// Pumps real time until [samples] has moved past [from] — one more
  /// measuring window landed — and the strip has rebuilt off it.
  Future<void> waitForSample(
    WidgetTester tester,
    int Function() samples,
  ) async {
    final from = samples();
    for (var i = 0; i < 50 && samples() == from; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(samples(), greaterThan(from), reason: 'the monitor never sampled');
    await tester.pump();
  }

  Color dot(WidgetTester tester) =>
      ((tester.widget<Container>(find.byKey(SystemLoadChip.dotKey)).decoration
              as BoxDecoration?)!
          .color)!;

  String rowText(WidgetTester tester, int index, int part) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(SystemLoadPopover.rowKey(index)),
          matching: find.byType(Text),
        ),
      )
      .elementAt(part)
      .data!;

  testWidgets('SYS turns red on one saturated thread although the 24-core '
      'average is low, and the popover names the threads', (tester) async {
    final sampler = ScriptedThreadCpuSampler(
      rates: {
        11: (name: '1.raster', percent: 40),
        12: (name: '1.ui', percent: 12),
        13: (name: '', percent: 28), // PortAudio's unnamed callback thread
      },
    );
    await boot(tester, sampler);

    // Beside CPU, which keeps showing the audio-callback budget.
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('SYS'), findsOneWidget);
    expect(
      tester.getRect(find.text('SYS')).left,
      greaterThan(tester.getRect(find.text('CPU')).right),
    );

    await waitForSample(tester, () => sampler.samples);
    expect(dot(tester), PhiColors.voice4, reason: 'busiest thread at 40 %');

    sampler.rates[14] = (name: 'isolate.swarm', percent: 91);
    await waitForSample(tester, () => sampler.samples);
    expect(dot(tester), PhiColors.hot, reason: 'one thread at 91 % of a core');

    await tester.tap(find.byKey(SystemLoadChip.chipKey));
    await tester.pumpAndSettle();

    final panel = find.byKey(SystemLoadPopover.panelKey);
    expect(panel, findsOneWidget);
    expect(rowText(tester, 0, 0), 'isolate.swarm');
    expect(rowText(tester, 0, 1), '91 %');
    expect(rowText(tester, 1, 0), '1.raster');
    expect(rowText(tester, 2, 0), 'thread 13');
    expect(rowText(tester, 2, 1), '28 %');
    expect(rowText(tester, 3, 0), '1.ui');
    // (91 + 40 + 28 + 12) % of one core over 24 cores.
    expect(find.text('process 7.1 % of 24 cores'), findsOneWidget);

    // It opens upward out of the strip and stays inside the window.
    final rect = tester.getRect(panel);
    expect(
      rect.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('SYS')).top),
    );
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1600));

    // Live while open: the swarm calms down, the raster thread leads.
    sampler.rates[14] = (name: 'isolate.swarm', percent: 2);
    await waitForSample(tester, () => sampler.samples);
    expect(rowText(tester, 0, 0), '1.raster');
    expect(dot(tester), PhiColors.voice4);

    // An outside click closes it.
    await tester.tapAt(const Offset(800, 400));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    await teardown(tester);
  });

  testWidgets('the host OS sampler (procfs on Linux, kernel32 on Windows) '
      "measures this process's real threads", (tester) async {
    final sampler = _CountingSampler(HostThreadCpuSampler.create()!);
    await boot(tester, sampler);

    // Spin the UI isolate inside one window so some real thread is clearly
    // busy, whatever the Flutter embedder named it.
    await waitForSample(tester, () => sampler.samples);
    final spin = Stopwatch()..start();
    while (spin.elapsedMilliseconds < 600) {}
    await waitForSample(tester, () => sampler.samples);

    await tester.tap(find.byKey(SystemLoadChip.chipKey));
    await tester.pumpAndSettle();

    expect(find.byKey(SystemLoadPopover.panelKey), findsOneWidget);
    expect(rowText(tester, 0, 0), isNotEmpty);
    final percent = int.parse(rowText(tester, 0, 1).split(' ').first);
    expect(percent, greaterThanOrEqualTo(20));
    expect(dot(tester), isNot(PhiColors.fg4));
    expect(find.textContaining('process '), findsOneWidget);
    expect(
      find.textContaining('of ${Platform.numberOfProcessors} core'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(800, 400));
    await tester.pumpAndSettle();
    await teardown(tester);
  }, skip: !(Platform.isLinux || Platform.isWindows));
}
