import 'system_load_level.dart';

/// One thread's CPU use over the last sampling window (issue #24) — a row of
/// the `SYS` popover.
class ThreadCpuUsage {
  /// [name] (OS thread [id]) ran for [percent] of one core over the window.
  const ThreadCpuUsage({
    required this.id,
    required this.name,
    required this.percent,
  });

  /// The OS thread id.
  final int id;

  /// The OS thread name; empty when the thread was never named.
  final String name;

  /// Percent of *one* core: 100 means the thread never left the CPU. Per-core
  /// rather than per-machine on purpose — a single saturated thread is the
  /// problem, however many idle cores sit beside it.
  final double percent;

  /// What the row shows: the name, or `thread <id>` for an unnamed thread.
  String get label => name.isEmpty ? 'thread $id' : name;

  /// The level this thread alone sits at.
  SystemLoadLevel get level => SystemLoadLevel.forPercent(percent);

  @override
  bool operator ==(Object other) =>
      other is ThreadCpuUsage &&
      other.id == id &&
      other.name == name &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(id, name, percent);

  @override
  String toString() => 'ThreadCpuUsage($label, $percent %)';
}
