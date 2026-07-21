import 'bus_tap.dart';

/// The production [BusTap] until the host bus tap engine dependency lands
/// (`yvanvds/yse-soundengine#389`, `yvanvds/dart-yse#43`) — every subscription
/// yields an empty stream, because nothing publishes to the host yet.
///
/// The seam is proven present and silent by tests; wiring in the live tap (or,
/// under test, a `FakeBusTap`) touches nothing but this default (design
/// `docs/design/live-coding.md` §9 step 1).
class NoOpBusTap implements BusTap {
  /// A const, shareable no-op — the default the engine wires in production.
  const NoOpBusTap();

  @override
  Stream<BusTapFrame> subscribe(String prefix) => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
