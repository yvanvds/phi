/// A source of the current wall-clock time — the seam that keeps `DateTime.now()`
/// out of the layers above.
///
/// Timestamps thread through the log domain (entry stamps, session-file names),
/// and scattering `DateTime.now()` through that code would make it untestable.
/// Callers depend on this interface instead; production wires [SystemClock] and
/// tests supply a fake with a fixed or advancing time.
abstract interface class Clock {
  /// The current instant.
  DateTime now();
}

/// The production [Clock]: reads the real system clock.
class SystemClock implements Clock {
  /// Creates a clock over `DateTime.now()`.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
