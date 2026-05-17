import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';
import 'status_chip.dart';

/// Bottom status strip — 24px. Shows live engine telemetry: audio thread CPU
/// load and cumulative missed callbacks. Other status comes online later.
class BottomStatus extends StatelessWidget {
  const BottomStatus({required this.engine, super.key});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PhiSpacing.bottomStatusHeight,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(top: BorderSide(color: PhiColors.line1)),
      ),
      child: StreamBuilder<EngineTelemetry>(
        stream: engine.telemetry,
        initialData: EngineTelemetry.zero,
        builder: (context, snapshot) {
          final t = snapshot.data ?? EngineTelemetry.zero;
          final cpuPct = (t.cpuLoad * 100).toStringAsFixed(1);
          return Row(
            children: [
              const Spacer(),
              StatusChip(label: 'CPU', value: '$cpuPct %'),
              StatusChip(label: 'DROPS', value: '${t.missedCallbacks}'),
            ],
          );
        },
      ),
    );
  }
}
