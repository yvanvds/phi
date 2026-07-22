import 'package:flutter/foundation.dart';

/// What booting the log found: the previous session ended **without** writing
/// its clean-shutdown marker, so it crashed (design
/// `docs/design/diagnostics.md` §6).
///
/// A non-null report from `SessionLog.boot` is the signal for the diagnostics
/// epic's crash notice (issue #272) to offer the previous session's log —
/// [previousLogName] is the file that holds "what happened". The journal's
/// recovery dialog covers the *project* side; this covers the *diagnostics* side.
@immutable
class CrashReport {
  /// Records that the previous session crashed, its log left at [previousLogName].
  const CrashReport({required this.previousLogName});

  /// The `phi-<timestamp>.log` file name of the crashed session.
  final String previousLogName;

  @override
  bool operator ==(Object other) =>
      other is CrashReport && other.previousLogName == previousLogName;

  @override
  int get hashCode => previousLogName.hashCode;

  @override
  String toString() => 'CrashReport(previousLogName: $previousLogName)';
}
