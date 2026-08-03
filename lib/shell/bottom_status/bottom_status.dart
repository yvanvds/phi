import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/session/session_state.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';
import '../diagnostics/audio_device_health.dart';
import '../diagnostics/log_panel_controller.dart';
import '../diagnostics/log_panel_toggle.dart';
import 'audio_device_chip.dart';
import 'midi_activity_dot.dart';
import 'panic_button.dart';
import 'status_chip.dart';

/// Bottom status strip — 24px. Shows live engine telemetry (CPU, buffer,
/// latency, drops), a `LIVE` dot that lights up when projection mode is on, the
/// **panic** button right of the dot (issue #264), an **audio-device health
/// chip** (issue #271), and a MIDI activity indicator that flashes on incoming
/// MIDI.
class BottomStatus extends StatelessWidget {
  /// Production constructor — binds to a live [PhiEngine]. [onPanic] routes the
  /// status-bar panic button (issue #264); the shell passes a handler that also
  /// resets the toolbar transport, defaulting to the engine's own
  /// [PhiEngine.panic] when a caller wires nothing extra.
  BottomStatus({
    required PhiEngine engine,
    required this.session,
    this.logPanel,
    this.audioHealth,
    this.onAudioSettings,
    VoidCallback? onPanic,
    super.key,
  }) : telemetry = engine.telemetry,
       midiActivity = engine.midiActivity,
       onPanic = onPanic ?? engine.panic;

  /// Constructor for widget tests — accepts the streams directly so they
  /// can be driven from a `StreamController` without spinning up the
  /// engine's periodic timer. [onPanic] defaults to a no-op so a test that
  /// doesn't exercise panic can omit it.
  const BottomStatus.fromStreams({
    required this.telemetry,
    required this.midiActivity,
    required this.session,
    this.logPanel,
    this.audioHealth,
    this.onAudioSettings,
    this.onPanic = _noPanic,
    super.key,
  });

  final Stream<EngineTelemetry> telemetry;
  final Stream<void> midiActivity;
  final SessionState session;

  /// The log-panel controller backing the status-bar log toggle + error badge
  /// (design `docs/design/diagnostics.md` §4, §5). `null` in the bare widget
  /// tests that don't exercise the log; the toggle is then omitted.
  final LogPanelController? logPanel;

  /// The live audio-device health the status-bar chip shows (design
  /// `docs/design/diagnostics.md` §5, issue #271). `null` in the bare widget
  /// tests that don't exercise it; the chip is then omitted.
  final ValueListenable<AudioDeviceHealth>? audioHealth;

  /// Opens the settings dialog's AUDIO section — the audio chip's click-through
  /// (design §5). `null` leaves the chip inert (no settings owner wired).
  final VoidCallback? onAudioSettings;

  /// The panic action the status-bar button runs (issue #264) — the shell wires
  /// this to `PhiEngine.panic`.
  final VoidCallback onPanic;

  static void _noPanic() {}

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
              const SizedBox(width: PhiSpacing.s3),
              PanicButton(onPanic: onPanic),
              const Spacer(),
              StatusChip(label: 'CPU', value: formatCpu(t.cpuLoad)),
              StatusChip(
                label: 'BUF',
                value: formatBuffer(t.bufferSize, t.sampleRate),
              ),
              StatusChip(label: 'LAT', value: formatLatency(t.latencyMs)),
              // The cumulative *stall event* count, not the engine's raw
              // device-stall gauge — showing the gauge made this flicker to `1`
              // once a second on a healthy device (issue #350).
              StatusChip(label: 'DROPS', value: '${t.audioStalls}'),
              if (audioHealth != null) ...[
                const SizedBox(width: PhiSpacing.s2),
                AudioDeviceChip(health: audioHealth!, onTap: onAudioSettings),
                const SizedBox(width: PhiSpacing.s2),
              ],
              MidiActivityDot(activity: midiActivity),
              if (logPanel != null) ...[
                const SizedBox(width: PhiSpacing.s3),
                LogPanelToggle(controller: logPanel!),
              ],
              const SizedBox(width: PhiSpacing.s3),
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
