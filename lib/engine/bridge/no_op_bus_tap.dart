import 'bus_tap.dart';

/// A [BusTap] that never delivers — every subscription yields an empty stream.
///
/// Production uses the gateway's session-bound `RealBusTap` (issue #480); this
/// stays for tests that want the control plane wired but silent.
class NoOpBusTap implements BusTap {
  /// A const, shareable no-op.
  const NoOpBusTap();

  @override
  Stream<BusTapFrame> subscribe(String prefix) => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
