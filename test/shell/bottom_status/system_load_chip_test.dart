import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/domain/system_load/system_load.dart';
import 'package:phi/domain/system_load/thread_cpu_usage.dart';
import 'package:phi/shell/bottom_status/system_load_chip.dart';
import 'package:phi/shell/bottom_status/system_load_popover.dart';

SystemLoad _load(List<(String, double)> threads) => SystemLoad(
  threads: [
    for (var i = 0; i < threads.length; i++)
      ThreadCpuUsage(id: 100 + i, name: threads[i].$1, percent: threads[i].$2),
  ],
  processPercent: 7.6,
  logicalCores: 24,
);

void main() {
  late ValueNotifier<SystemLoad> load;

  setUp(() => load = ValueNotifier(SystemLoad.pending));
  tearDown(() => load.dispose());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: SystemLoadChip(load: load),
        ),
      ),
    ),
  );

  Color dot(WidgetTester tester) =>
      ((tester.widget<Container>(find.byKey(SystemLoadChip.dotKey)).decoration
              as BoxDecoration?)!
          .color)!;

  testWidgets('the dot follows the busiest thread: muted, green, amber, red', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('SYS'), findsOneWidget);
    expect(dot(tester), PhiColors.fg4, reason: 'no window measured yet');

    load.value = _load([('1.raster', 40), ('phi', 3)]);
    await tester.pump();
    expect(dot(tester), PhiColors.voice4);

    load.value = _load([('1.raster', 64), ('phi', 3)]);
    await tester.pump();
    expect(dot(tester), PhiColors.warm);

    // A 24-core average of a few percent still reads red: one thread is pegged.
    load.value = _load([('swarm', 91), ('1.raster', 64)]);
    await tester.pump();
    expect(dot(tester), PhiColors.hot);

    load.value = SystemLoad.unavailable;
    await tester.pump();
    expect(dot(tester), PhiColors.fg4);
  });

  test('tooltip names the busiest thread, or why there is none', () {
    expect(
      SystemLoadChip.tooltipFor(SystemLoad.unavailable),
      'per-thread CPU not available on this system',
    );
    expect(
      SystemLoadChip.tooltipFor(SystemLoad.pending),
      'measuring per-thread CPU…',
    );
    expect(
      SystemLoadChip.tooltipFor(_load([('swarm', 91.4)])),
      'busiest thread: swarm 91 % of a core — click for every thread',
    );
  });

  testWidgets('click opens the per-thread popover; it stays live; an outside '
      'click closes it', (tester) async {
    load.value = _load([('swarm', 91), ('1.raster', 64), ('', 28)]);
    await pump(tester);
    expect(find.byKey(SystemLoadPopover.panelKey), findsNothing);

    await tester.tap(find.byKey(SystemLoadChip.chipKey));
    await tester.pump();

    expect(find.byKey(SystemLoadPopover.panelKey), findsOneWidget);
    final row0 = find.byKey(SystemLoadPopover.rowKey(0));
    expect(
      find.descendant(of: row0, matching: find.text('swarm')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row0, matching: find.text('91 %')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SystemLoadPopover.rowKey(2)),
        matching: find.text('thread 102'),
      ),
      findsOneWidget,
      reason: 'an unnamed thread is labelled by its id',
    );
    expect(find.text('process 7.6 % of 24 cores'), findsOneWidget);
    // The panel opens upward from the bottom strip, fully on screen.
    final panel = tester.getRect(find.byKey(SystemLoadPopover.panelKey));
    final chip = tester.getRect(find.byKey(SystemLoadChip.chipKey));
    expect(panel.bottom, lessThanOrEqualTo(chip.top));
    expect(panel.top, greaterThanOrEqualTo(0));

    // A new window lands while it is open.
    load.value = _load([('1.raster', 70), ('swarm', 2)]);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(SystemLoadPopover.rowKey(0)),
        matching: find.text('1.raster'),
      ),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(find.byKey(SystemLoadPopover.panelKey), findsNothing);
  });

  testWidgets(
    'the popover caps the list at ${SystemLoadPopover.maxRows} rows',
    (tester) async {
      load.value = _load([for (var i = 0; i < 12; i++) ('t$i', 50.0 - i)]);
      await pump(tester);
      await tester.tap(find.byKey(SystemLoadChip.chipKey));
      await tester.pump();

      expect(
        find.byKey(SystemLoadPopover.rowKey(SystemLoadPopover.maxRows - 1)),
        findsOneWidget,
      );
      expect(
        find.byKey(SystemLoadPopover.rowKey(SystemLoadPopover.maxRows)),
        findsNothing,
      );
    },
  );

  testWidgets('the popover explains an unavailable, pending or idle load', (
    tester,
  ) async {
    load.value = SystemLoad.unavailable;
    await pump(tester);
    await tester.tap(find.byKey(SystemLoadChip.chipKey));
    await tester.pump();
    expect(
      find.text('per-thread CPU is not available on this system'),
      findsOneWidget,
    );

    load.value = SystemLoad.pending;
    await tester.pump();
    expect(find.text('measuring…'), findsOneWidget);

    load.value = _load([('phi', 0), ('1.ui', 0.01)]);
    await tester.pump();
    expect(find.text('every thread is idle'), findsOneWidget);
    expect(find.byKey(SystemLoadPopover.rowKey(0)), findsNothing);
  });
}
