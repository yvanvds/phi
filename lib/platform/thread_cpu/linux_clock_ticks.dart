import 'dart:ffi';

/// The kernel's clock-tick rate (`sysconf(_SC_CLK_TCK)`), the unit of the
/// `utime` / `stime` fields in `/proc/<pid>/task/<tid>/stat` (issue #24).
class LinuxClockTicks {
  LinuxClockTicks._();

  /// `_SC_CLK_TCK` in glibc and musl on Linux.
  static const int _scClkTck = 2;

  /// The value virtually every Linux build uses — the fallback when `sysconf`
  /// cannot be resolved or reports nonsense.
  static const int fallback = 100;

  /// Ticks per second, read once from libc.
  static int perSecond() {
    try {
      final sysconf = DynamicLibrary.process()
          .lookupFunction<Long Function(Int32), int Function(int)>('sysconf');
      final ticks = sysconf(_scClkTck);
      return ticks > 0 ? ticks : fallback;
    } on Object {
      return fallback;
    }
  }
}
