import 'dart:async';

import 'package:yse/yse.dart' as yse;

import 'bus_tap.dart';

/// The production [BusTap] over dart-yse's host bus tap, `Bus.tap(prefix)`
/// (yse 0.2.0 / libYSE 3.1, issue #480).
///
/// **Delivery and threading.** `Bus.tap` registers a native tap whose callback
/// is a `NativeCallable.isolateLocal`: the engine invokes it on the control
/// thread — the isolate that initialised the engine and drives
/// `System.update()` — inline for a control-thread publish, otherwise during
/// the next `update()` tick for a publish the script or audio thread made.
/// Never on the audio thread. The wrapper copies each frame out of engine
/// memory and queues it on a broadcast stream, so a frame reaches the
/// [ControlPlaneDispatcher] as an ordinary main-isolate event: nothing polls,
/// nothing blocks the UI thread, and the audio thread never waits on Dart.
///
/// **Session lifecycle.** A yse tap belongs to one engine session —
/// `System.close()` releases every native tap and ends its stream. So this
/// adapter never holds a tap across sessions: [subscribe] hands out a stream
/// that attaches the native tap only when it gains a listener, and only while
/// [sessionOpen] says a session is running; it detaches when the listener
/// cancels. The engine rebuilds its dispatcher — and so re-subscribes — on
/// every start and after an audio-session restart (issue #448). Outside a
/// session nothing native is touched (issue #421): a subscribe yields a stream
/// that simply closes, and a cancel after `close()` only drops the reference,
/// because `System.close()` already released the native tap.
///
/// **Prefix semantics.** The engine's tap is a byte-wise prefix match (`phi.ctl`
/// also matches `phi.ctlx`); [BusTap] is segment-aware, so frames outside
/// [busAddressMatchesPrefix] are filtered here. A valueless `BusBang` has no
/// [BusValue] counterpart — no `phi.ctl` verb carries one — and is dropped.
class RealBusTap implements BusTap {
  /// [sessionOpen] reports whether an engine session is running — the
  /// gateway's own session flag, so the tap and every other native write share
  /// one notion of "the engine is up".
  RealBusTap({required this._sessionOpen});

  final bool Function() _sessionOpen;
  final Map<StreamController<BusTapFrame>, void Function()> _open = {};
  bool _disposed = false;

  @override
  Stream<BusTapFrame> subscribe(String prefix) {
    if (_disposed) return const Stream.empty();
    // Cancelled in `detach` (the stream's onCancel, or [dispose]) while the
    // session is live; after `close()` the engine has already ended it.
    // ignore: cancel_subscriptions
    StreamSubscription<yse.BusFrame>? native;
    late final StreamController<BusTapFrame> controller;

    void detach() {
      final sub = native;
      native = null;
      // Cancelling releases the native tap — only valid on a live session.
      // After `close()` the engine already released it and ended the stream.
      if (sub != null && _sessionOpen()) unawaited(sub.cancel());
    }

    controller = StreamController<BusTapFrame>.broadcast(
      onListen: () {
        if (_disposed || !_sessionOpen()) {
          unawaited(controller.close());
          return;
        }
        native = yse.Bus.tap(prefix).listen(
          (frame) {
            if (!busAddressMatchesPrefix(frame.address, prefix)) return;
            final value = toBusValue(frame.value);
            if (value != null) {
              controller.add(BusTapFrame(frame.address, value));
            }
          },
          // `System.close()` ended the session's tap: this stream is done too.
          onDone: () {
            native = null;
            unawaited(controller.close());
          },
        );
      },
      onCancel: detach,
    );
    _open[controller] = detach;
    unawaited(controller.done.then((_) => _open.remove(controller)));
    return controller.stream;
  }

  /// Maps a yse bus value onto Phi's [BusValue], or `null` for a bang.
  static BusValue? toBusValue(yse.BusValue value) => switch (value) {
    yse.BusInt(:final value) => BusInt(value),
    yse.BusFloat(:final value) => BusFloat(value),
    yse.BusString(:final value) => BusString(value),
    yse.BusList(:final values) => BusFloatList(values),
    yse.BusBang() => null,
  };

  /// Detaches every native tap still attached (gated on the session) and ends
  /// every stream handed out. Safe to call more than once.
  @override
  Future<void> dispose() async {
    _disposed = true;
    final open = {..._open};
    _open.clear();
    for (final MapEntry(key: controller, value: detach) in open.entries) {
      detach();
      await controller.close();
    }
  }
}
