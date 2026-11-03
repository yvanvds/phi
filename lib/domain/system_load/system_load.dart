import 'system_load_level.dart';
import 'thread_cpu_usage.dart';

/// The per-thread CPU picture of the Phi process over the last sampling window
/// (issue #24): what the status bar's `SYS` chip and its popover show.
///
/// Threads, not cores: the scheduler moves threads between cores constantly
/// (and more so on P-core / E-core parts), so a per-core view shows churn. A
/// thread has a role — "1.raster at 64 %" says what to fix.
class SystemLoad {
  /// A measured window.
  const SystemLoad({
    required this.threads,
    required this.processPercent,
    required this.logicalCores,
  }) : available = true;

  const SystemLoad._empty({required this.available})
    : threads = const [],
      processPercent = 0,
      logicalCores = 0;

  /// Sampling is not possible here (no sampler for this OS, or it failed).
  static const SystemLoad unavailable = SystemLoad._empty(available: false);

  /// Sampling runs but no window has completed yet.
  static const SystemLoad pending = SystemLoad._empty(available: true);

  /// Whether per-thread sampling works on this machine at all.
  final bool available;

  /// Every thread measured over the window, busiest first.
  final List<ThreadCpuUsage> threads;

  /// The whole process's CPU use as a percent of *all* logical cores — the
  /// number that hides saturation on a many-core machine, shown only as
  /// context beside the per-thread rows.
  final double processPercent;

  /// The logical core count [processPercent] is normalised over.
  final int logicalCores;

  /// The busiest thread, or `null` before the first window.
  ThreadCpuUsage? get busiest => threads.isEmpty ? null : threads.first;

  /// The dot colour: the busiest thread's level, [SystemLoadLevel.unknown]
  /// before the first window or when unavailable.
  SystemLoadLevel get level => busiest?.level ?? SystemLoadLevel.unknown;

  /// The [count] busiest threads that did any measurable work (at least
  /// [minPercent] of a core) — the popover's rows.
  List<ThreadCpuUsage> top(int count, {double minPercent = 0.1}) => threads
      .where((t) => t.percent >= minPercent)
      .take(count)
      .toList(growable: false);
}
