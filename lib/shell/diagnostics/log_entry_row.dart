import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/log/log_entry.dart';
import '../../domain/log/log_level.dart';

/// One line in the log panel (design `docs/design/diagnostics.md` §4): the
/// timestamp, a severity-tinted level tag, the source tag, and the message.
///
/// Purely presentational and text-based, so the ambient [SelectionArea] the
/// panel wraps the list in lets the performer drag-select any span and copy it.
/// A multi-line message (a Python traceback) wraps and keeps its own newlines.
class LogEntryRow extends StatelessWidget {
  /// Renders [entry].
  const LogEntryRow({required this.entry, super.key});

  /// The log line to draw.
  final LogEntry entry;

  static Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return PhiColors.hot;
      case LogLevel.warning:
        return PhiColors.warm;
      case LogLevel.info:
        return PhiColors.cool;
      case LogLevel.debug:
        return PhiColors.fg3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _levelColor(entry.level);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s3,
        vertical: PhiSpacing.s0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _clock(entry.time),
            style: PhiType.monoS().copyWith(color: PhiColors.fg3),
          ),
          const SizedBox(width: PhiSpacing.s2),
          SizedBox(
            width: 58,
            child: Text(
              entry.level.wireName.toUpperCase(),
              style: PhiType.monoS().copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              entry.source.wireName,
              style: PhiType.monoS().copyWith(color: PhiColors.fg2),
            ),
          ),
          const SizedBox(width: PhiSpacing.s2),
          Expanded(
            child: Text(
              entry.text,
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
            ),
          ),
        ],
      ),
    );
  }

  /// `HH:MM:SS.mmm` — the wall time, seconds resolution plus millis; the date is
  /// implied by the session and left off to keep the row narrow.
  static String _clock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$h:$mi:$s.$ms';
  }
}
