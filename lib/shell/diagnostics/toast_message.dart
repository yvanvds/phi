import '../../domain/log/log_level.dart';

/// One transient toast the notice channel is showing (design
/// `docs/design/diagnostics.md` §3).
///
/// Immutable and identity-keyed: [id] lets the overlay track a toast across
/// rebuilds (its entry animation, its auto-dismiss) as siblings come and go.
/// [level] tints the accent — a red edge for an error, amber for a warning.
class ToastMessage {
  /// A toast [id]entified for the overlay, carrying [text] at [level].
  const ToastMessage({
    required this.id,
    required this.text,
    required this.level,
  });

  /// A monotonic id assigned by the [ToastController] when the toast is shown.
  final int id;

  /// The human-readable line shown to the performer.
  final String text;

  /// The severity, mirrored from the log entry — drives the accent colour.
  final LogLevel level;
}
