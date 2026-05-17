import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/button/primary_button.dart';
import '../../design/widgets/meter/peak_meter.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';
import '../surface.dart';

/// Phase 1 Mix surface: a single panel with one play/stop button bound to
/// the engine's built-in audio test signal, and one peak meter driven by
/// engine CPU load as a stand-in until dart-yse exposes channel peak level.
class MixSurface extends Surface {
  const MixSurface({required this.engine, super.key});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(PhiSpacing.s5),
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(color: PhiColors.line1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CHANNEL · MASTER', style: PhiType.caption()),
              const SizedBox(height: PhiSpacing.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: engine.testSignal,
                      builder: (context, armed, _) => PrimaryButton(
                        label: armed ? 'stop sine' : 'play sine',
                        isArmed: armed,
                        onPressed: () => engine.setTestSignal(on: !armed),
                      ),
                    ),
                  ),
                  const SizedBox(width: PhiSpacing.s3),
                  StreamBuilder<EngineTelemetry>(
                    stream: engine.telemetry,
                    initialData: EngineTelemetry.zero,
                    builder: (context, snapshot) {
                      final t = snapshot.data ?? EngineTelemetry.zero;
                      return PeakMeter(level: t.cpuLoad);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
