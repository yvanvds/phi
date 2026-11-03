import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/system_load/system_load.dart';
import '../../domain/system_load/thread_cpu_usage.dart';
import 'system_load_colours.dart';

/// The panel the `SYS` chip opens (issue #24): the busiest threads of the Phi
/// process by CPU, each as a percent of one core, with the whole-process
/// figure over all cores as context underneath.
class SystemLoadPopover extends StatelessWidget {
  /// Shows [load]; rebuilt by the chip on every new window.
  const SystemLoadPopover({required this.load, super.key});

  final SystemLoad load;

  /// How many threads the panel lists.
  static const int maxRows = 8;

  static const Key panelKey = Key('SystemLoadPopover.panel');

  /// Key of the row at [index] (0 = busiest) — what tests target.
  static Key rowKey(int index) => Key('SystemLoadPopover.row.$index');

  /// `64 %` — a thread's share of one core, rounded to a whole percent.
  static String formatThreadPercent(double percent) => '${percent.round()} %';

  /// `3.2 % of 24 cores` — the whole process over every logical core.
  static String formatProcess(double percent, int cores) =>
      '${percent.toStringAsFixed(1)} % of $cores '
      '${cores == 1 ? 'core' : 'cores'}';

  @override
  Widget build(BuildContext context) {
    return Container(
      key: panelKey,
      width: 280,
      padding: const EdgeInsets.all(PhiSpacing.s3),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: PhiColors.line2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('THREADS BY CPU', style: PhiType.caption()),
          const SizedBox(height: PhiSpacing.s1),
          Text(
            'percent of one core',
            style: PhiType.caption().copyWith(color: PhiColors.fg3),
          ),
          const SizedBox(height: PhiSpacing.s3),
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    if (!load.available) {
      return [_note('per-thread CPU is not available on this system')];
    }
    if (load.threads.isEmpty) return [_note('measuring…')];
    final rows = load.top(maxRows);
    return [
      if (rows.isEmpty) _note('every thread is idle'),
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SizedBox(height: PhiSpacing.s1),
        _ThreadRow(key: rowKey(i), usage: rows[i]),
      ],
      const SizedBox(height: PhiSpacing.s3),
      Text(
        'process ${formatProcess(load.processPercent, load.logicalCores)}',
        style: PhiType.caption().copyWith(color: PhiColors.fg3),
      ),
    ];
  }

  static Widget _note(String text) =>
      Text(text, style: PhiType.small().copyWith(color: PhiColors.fg2));
}

/// One thread: its name, a bar of its share of one core, and the percent.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.usage, super.key});

  final ThreadCpuUsage usage;

  @override
  Widget build(BuildContext context) {
    final colour = SystemLoadColours.forLevel(usage.level);
    return Row(
      children: [
        Expanded(
          child: Text(
            usage.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PhiType.monoS().copyWith(color: PhiColors.fg1),
          ),
        ),
        const SizedBox(width: PhiSpacing.s2),
        SizedBox(
          width: 56,
          height: 4,
          child: ClipRRect(
            borderRadius: PhiRadii.allPill,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: PhiColors.bg4)),
                FractionallySizedBox(
                  widthFactor: (usage.percent / 100).clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: ColoredBox(color: colour),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: PhiSpacing.s2),
        SizedBox(
          width: 40,
          child: Text(
            SystemLoadPopover.formatThreadPercent(usage.percent),
            textAlign: TextAlign.right,
            style: PhiType.monoS().copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}
