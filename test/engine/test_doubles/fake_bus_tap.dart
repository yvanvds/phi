import 'dart:async';

import 'package:phi/engine/bridge/bus_tap.dart';

/// A [BusTap] test double that stands in for the not-yet-landed engine tap.
///
/// Tests subscribe to a prefix like the real host would, then call [publish] to
/// simulate an engine-side bus write; the frame is delivered to every
/// subscription whose prefix covers the address (segment-aware, via
/// [busAddressMatchesPrefix]) — exactly the prefix semantics the C API will
/// have. This makes the whole live-coding control plane testable before the
/// engine dependency exists (design `docs/design/live-coding.md` §9 step 1).
class FakeBusTap implements BusTap {
  final Map<String, StreamController<BusTapFrame>> _byPrefix = {};

  /// Every frame handed to [publish], in order — a convenience for assertions
  /// that don't care about the streaming path.
  final List<BusTapFrame> published = [];

  @override
  Stream<BusTapFrame> subscribe(String prefix) => _byPrefix
      .putIfAbsent(prefix, () => StreamController<BusTapFrame>.broadcast())
      .stream;

  /// Simulate the engine publishing [value] to [address]. Delivered to every
  /// active subscription whose prefix covers [address].
  void publish(String address, BusValue value) {
    final frame = BusTapFrame(address, value);
    published.add(frame);
    for (final entry in _byPrefix.entries) {
      if (busAddressMatchesPrefix(address, entry.key)) {
        entry.value.add(frame);
      }
    }
  }

  @override
  Future<void> dispose() async {
    for (final controller in _byPrefix.values) {
      if (!controller.isClosed) await controller.close();
    }
    _byPrefix.clear();
  }
}
