import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/session/session_state.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';
import 'midi_activity_dot.dart';
import 'status_chip.dart';

/// Bottom status strip — 24px. Shows live engine telemetry (CPU, buffer,
/// latency, drops), a `LIVE` dot that lights up when projection mode is on,
/// and a MIDI activity indicator that flashes on incoming MIDI.
class BottomStatus extends StatelessWidget {
  /// Production constructor — binds to a live [PhiEngine].
  BottomStatus({required PhiEngine engine, required this.session, super.key})
    : telemetry = engine.telemetry,
      midiActivity = engine.midiActivity;

  /// Constructor for widget tests — accepts the streams directly so they
  /// can be driven from a `StreamController` without spinning up the
  /// engine's periodic timer.
  const BottomStatus.fromStreams({
    required this.telemetry,
    required this.midiActivity,
    required this.session,
    super.key,
  });

  final Stream<EngineTelemetry> telemetry;
  final Stream<void> midiActivity;
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
        stream: telemetry,
        initialData: EngineTelemetry.zero,
        builder: (context, snapshot) {
          final t = snapshot.data ?? EngineTelemetry.zero;
          return Row(
            children: [
              const SizedBox(width: PhiSpacing.s3),
              _LiveDot(session: session),
              const Spacer(),
              StatusChip(label: 'CPU', value: formatCpu(t.cpuLoad)),
              StatusChip(
                label: 'BUF',
                value: formatBuffer(t.bufferSize, t.sampleRate),
              ),
              StatusChip(label: 'LAT', value: formatLatency(t.latencyMs)),
              StatusChip(label: 'DROPS', value: '${t.missedCallbacks}'),
              MidiActivityDot(activity: midiActivity),
            ],
          );
        },
      ),
    );
  }

  @visibleForTesting
  static String formatCpu(double cpuLoad) =>
      '${(cpuLoad * 100).toStringAsFixed(1)} %';

  /// Matches the design-system status preview: "128 / 48k" — frames per
  /// callback and the sample rate rounded to the nearest kHz. Shows `—`
  /// before a device is open.
  @visibleForTesting
  static String formatBuffer(int bufferSize, double sampleRate) {
    if (bufferSize <= 0 || sampleRate <= 0) return '—';
    final khz = (sampleRate / 1000).round();
    return '$bufferSize / ${khz}k';
  }

  @visibleForTesting
  static String formatLatency(double ms) {
    if (ms <= 0) return '—';
    return '${ms.toStringAsFixed(1)} ms';
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
