import 'dart:async';

import 'package:phi/engine/bridge/bus_tap.dart';

/// A [BusTap] test double that stands in for the engine's host bus tap
/// (`RealBusTap`, issue #480) when a test runs without the native engine.
///
/// Tests subscribe to a prefix like the real host would, then call [publish] to
/// simulate an engine-side bus write; the frame is delivered to every
/// subscription whose prefix covers the address (segment-aware, via
/// [busAddressMatchesPrefix]) — exactly the prefix semantics the C API will
/// has.
///
/// Standalone (no [sessionOpen]) it is always live — the injected tap the
/// control-plane tests drive directly. [FakeYseGateway.busTap] instead binds
/// one to the fake's session, reproducing the real tap's lifecycle (issues
/// #421, #480): a subscribe outside a session yields an empty stream, a
/// publish outside one throws (yse's `Bus.publish` raises
/// `YSE_ERR_NOT_INITIALIZED`), and [endSession] — the fake's `close()` — ends
/// every stream, as `System.close()` does.
class FakeBusTap implements BusTap {
  FakeBusTap({this._sessionOpen});

  final bool Function()? _sessionOpen;
  final Map<String, StreamController<BusTapFrame>> _byPrefix = {};

  bool get _live => _sessionOpen?.call() ?? true;

  /// Every frame handed to [publish], in order — a convenience for assertions
  /// that don't care about the streaming path.
  final List<BusTapFrame> published = [];

  @override
  Stream<BusTapFrame> subscribe(String prefix) {
    if (!_live) return const Stream.empty();
    return _byPrefix
        .putIfAbsent(prefix, () => StreamController<BusTapFrame>.broadcast())
        .stream;
  }

  /// Simulate the engine publishing [value] to [address]. Delivered to every
  /// active subscription whose prefix covers [address].
  void publish(String address, BusValue value) {
    if (!_live) {
      throw StateError('bus publish to "$address" with no engine session');
    }
    final frame = BusTapFrame(address, value);
    published.add(frame);
    for (final entry in _byPrefix.entries) {
      if (busAddressMatchesPrefix(address, entry.key)) {
        entry.value.add(frame);
      }
    }
  }

  /// The session closed: end every stream, as `System.close()` releases every
  /// native tap. A later subscribe (in the next session) starts fresh.
  void endSession() {
    for (final controller in _byPrefix.values) {
      unawaited(controller.close());
    }
    _byPrefix.clear();
  }

  @override
  Future<void> dispose() async {
    for (final controller in _byPrefix.values) {
      if (!controller.isClosed) await controller.close();
    }
    _byPrefix.clear();
  }
}
