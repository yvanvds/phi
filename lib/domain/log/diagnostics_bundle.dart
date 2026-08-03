import 'log_entry.dart';
import 'log_transcript.dart';

/// The paste-ready diagnostics report (design `docs/design/diagnostics.md` §6,
/// issue #272): one block a solo dev drops into an issue filed against
/// themselves — app + libYSE versions, the resolved `YSE_DLL_PATH`, the device
/// and its live audio state, the open project path, and the tail of the log.
///
/// Pure Dart and value-shaped: the shell (`DiagnosticsReport`) gathers the live
/// facts off the engine / log / project into these primitive fields, and
/// [render] turns them into text. Keeping the assembly here — with no engine or
/// Flutter types — means the "complete and stable-ordered" contract is unit-
/// tested against plain fakes.
///
/// **Section order is stable by design** so two reports taken days apart diff
/// cleanly; nothing is redacted (a single-user, local-only machine).
class DiagnosticsBundle {
  /// Assembles a bundle from already-resolved facts. [log] is the full ring
  /// buffer (oldest first); only its last [logLineLimit] lines are rendered.
  const DiagnosticsBundle({
    required this.appVersion,
    required this.engineVersion,
    required this.libraryPath,
    required this.device,
    required this.sampleRate,
    required this.bufferSize,
    required this.outputLatencyMs,
    required this.layout,
    required this.audioStalls,
    required this.peakStallTicks,
    required this.projectPath,
    required this.log,
    this.logLineLimit = defaultLogLineLimit,
  }) : assert(logLineLimit > 0, 'logLineLimit must be positive');

  /// The design's tail size — "the last 200 log lines".
  static const int defaultLogLineLimit = 200;

  /// Phi's own version string.
  final String appVersion;

  /// The libYSE / engine version, as the engine reports it.
  final String engineVersion;

  /// The resolved `YSE_DLL_PATH` (or a "bundled library" note when unset).
  final String libraryPath;

  /// The audio device actually open, already formatted (e.g. `Alpha · WASAPI`).
  final String device;

  /// The open device's sample rate in Hz; `0` when no device is open.
  final double sampleRate;

  /// The open device's frames-per-callback; `0` when no device is open.
  final int bufferSize;

  /// The open device's output latency in milliseconds; `0` when none is open.
  final double outputLatencyMs;

  /// The speaker layout the device was opened with (e.g. `stereo`, `5.1`).
  final String layout;

  /// How many times the audio device went silent long enough to count as a
  /// stall this session — the drop counter as `DROPS` shows it (issue #350).
  final int audioStalls;

  /// The worst run of consecutive engine control ticks with no audio callback
  /// seen this session — how deep the worst stall got, in ticks.
  final int peakStallTicks;

  /// The open project's `.phi` folder, or `null` for an unsaved / no project.
  final String? projectPath;

  /// The unified log's buffered entries, oldest first.
  final List<LogEntry> log;

  /// How many trailing log lines the report carries (default 200).
  final int logLineLimit;

  /// The audio read-back line — the live state, or a plain note when nothing is
  /// open (the [sampleRate] being `0` is the "no device" signal).
  String get _audioState => sampleRate > 0
      ? '${sampleRate.toStringAsFixed(0)} Hz · $bufferSize frames · '
            '${outputLatencyMs.toStringAsFixed(1)} ms latency · $layout'
      : 'no device open';

  /// Renders the whole bundle to one paste-ready plain-text block, sections in a
  /// fixed order (versions → paths → audio → project → log).
  String render() {
    final tail = log.length > logLineLimit
        ? log.sublist(log.length - logLineLimit)
        : log;
    final transcript = tail.isEmpty
        ? '(no log entries)'
        : LogTranscript.of(tail);
    return 'Phi diagnostics\n'
        'App version: $appVersion\n'
        'libYSE version: $engineVersion\n'
        'YSE_DLL_PATH: $libraryPath\n'
        'Active device: $device\n'
        'Active state: $_audioState\n'
        'Audio stalls: $audioStalls (worst run $peakStallTicks control ticks '
        'with no callback)\n'
        'Open project: ${projectPath ?? '(no project open)'}\n'
        'Log (last ${tail.length} lines):\n'
        '$transcript';
  }
}
