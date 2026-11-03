/// How hard the busiest thread of the Phi process is working (issue #24) — the
/// colour of the `SYS` dot in the status bar.
enum SystemLoadLevel {
  /// No figure yet: sampling is unavailable on this OS, or only one snapshot
  /// has been taken so there is no window to measure over.
  unknown,

  /// The busiest thread has headroom (below [busyPercent]).
  ok,

  /// The busiest thread is past [busyPercent] of one core — worth watching.
  busy,

  /// The busiest thread is at or past [saturatedPercent] of one core — it is
  /// close to falling behind.
  saturated;

  /// Percent of one core at which a thread counts as [busy].
  static const double busyPercent = 60;

  /// Percent of one core at which a thread counts as [saturated].
  static const double saturatedPercent = 85;

  /// The level a thread running at [percent] of one core sits at.
  static SystemLoadLevel forPercent(double percent) {
    if (percent >= saturatedPercent) return saturated;
    if (percent >= busyPercent) return busy;
    return ok;
  }
}
