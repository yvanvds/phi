import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/session/session_state.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';
import 'status_chip.dart';

/// Bottom status strip — 24px. Shows live engine telemetry (CPU load, missed
/// callbacks) and a `LIVE` dot that lights up when projection mode is on.
class BottomStatus extends StatelessWidget {
  const BottomStatus({required this.engine, required this.session, super.key});

  final PhiEngine engine;
  final SessionState session;

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
              const SizedBox(width: PhiSpacing.s3),
              _LiveDot(session: session),
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

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: session.projection,
      builder: (context, on, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: on ? PhiColors.live : PhiColors.fg4,
              shape: BoxShape.circle,
              boxShadow: on
                  ? const [
                      BoxShadow(color: PhiColors.voice1Soft, blurRadius: 8),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: PhiSpacing.s2),
          Text(
            'LIVE',
            style: PhiType.caption().copyWith(
              color: on ? PhiColors.live : PhiColors.fg3,
            ),
          ),
        ],
      ),
    );
  }
}
