import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/bridge/control_plane_dispatcher.dart';
import 'package:phi/engine/bridge/real_bus_tap.dart';
import 'package:phi/engine/bridge/real_yse_gateway.dart';
import 'package:yse/yse.dart' as yse;

/// [RealBusTap] against the real engine (issue #480): frames published with
/// yse's `Bus.publish` — the path a script's `yse.send(...)` takes — arrive on
/// the gateway's session-bound tap, and the tap follows the session lifecycle
/// (#421): nothing native is touched outside a session, `close()` ends the
/// stream, and a fresh subscribe after the next init delivers again.
///
/// Runs headless on an offline session (yse 0.2.0 bundles `libyse` for
/// `flutter test`).
void main() {
  late RealYseGateway gateway;
  var sessionUp = false;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  void open() {
    gateway.initOffline();
    sessionUp = true;
  }

  void close() {
    sessionUp = false;
    gateway.close();
  }

  setUp(() => gateway = RealYseGateway());

  tearDown(() {
    if (sessionUp) close();
  });

  test('delivers a phi.ctl publish of every Phi value type', () async {
    open();
    final received = <BusTapFrame>[];
    final sub = gateway.busTap
        .subscribe(ControlPlaneDispatcher.prefix)
        .listen(received.add);
    addTearDown(sub.cancel);

    yse.Bus.publish('phi.ctl.state.fire', const yse.BusString('verse'));
    yse.Bus.publish('phi.ctl.clip.drums.play', const yse.BusInt(1));
    yse.Bus.publish('phi.ctl.fx.reverb.impact', const yse.BusFloat(0.25));
    yse.Bus.publish('phi.ctl.voice.bells.note', const yse.BusList([60, 100]));
    await flush();

    expect(received, const [
      BusTapFrame('phi.ctl.state.fire', BusString('verse')),
      BusTapFrame('phi.ctl.clip.drums.play', BusInt(1)),
      BusTapFrame('phi.ctl.fx.reverb.impact', BusFloat(0.25)),
      BusTapFrame('phi.ctl.voice.bells.note', BusFloatList([60, 100])),
    ]);
  });

  test('is segment-aware over the byte-wise native tap, and drops '
      'bangs', () async {
    open();
    final received = <BusTapFrame>[];
    final sub = gateway.busTap.subscribe('phi.ctl').listen(received.add);
    addTearDown(sub.cancel);

    yse.Bus.publish('phi.ctlx.state.fire', const yse.BusString('verse'));
    yse.Bus.publish('phi.other', const yse.BusInt(1));
    yse.Bus.publish('phi.ctl.var.go', const yse.BusBang());
    yse.Bus.publish('phi.ctl', const yse.BusInt(7));
    await flush();

    expect(received, const [BusTapFrame('phi.ctl', BusInt(7))]);
  });

  test('a cancelled subscription releases the native tap', () async {
    open();
    final received = <BusTapFrame>[];
    final sub = gateway.busTap.subscribe('phi.ctl').listen(received.add);
    await sub.cancel();

    yse.Bus.publish('phi.ctl.var.section', const yse.BusString('b'));
    await flush();
    expect(received, isEmpty);
  });

  test('outside a session a subscribe touches nothing native and simply '
      'ends', () async {
    // `Bus.tap` itself throws before init — the gate keeps it from running.
    final done = Completer<void>();
    final received = <BusTapFrame>[];
    gateway.busTap
        .subscribe('phi.ctl')
        .listen(received.add, onDone: done.complete);
    await done.future;
    expect(received, isEmpty);
  });

  test('close() ends the stream; the tap delivers again after a restart '
      '(#448)', () async {
    open();
    final first = <BusTapFrame>[];
    final ended = Completer<void>();
    final sub = gateway.busTap
        .subscribe('phi.ctl')
        .listen(first.add, onDone: ended.complete);

    yse.Bus.publish('phi.ctl.var.section', const yse.BusString('a'));
    await flush();
    close();
    await ended.future;
    // Cancelling after close() is safe: the engine already released the tap.
    await sub.cancel();
    expect(first, const [BusTapFrame('phi.ctl.var.section', BusString('a'))]);

    open();
    final second = <BusTapFrame>[];
    final again = gateway.busTap.subscribe('phi.ctl').listen(second.add);
    addTearDown(again.cancel);
    yse.Bus.publish('phi.ctl.var.section', const yse.BusString('b'));
    await flush();
    expect(second, const [BusTapFrame('phi.ctl.var.section', BusString('b'))]);
    expect(first, hasLength(1), reason: 'the old session hears nothing');
  });

  test(
    'dispose detaches every live subscription and ends its stream',
    () async {
      open();
      final tap = RealBusTap(sessionOpen: () => sessionUp);
      final received = <BusTapFrame>[];
      final ended = Completer<void>();
      tap.subscribe('phi.ctl').listen(received.add, onDone: ended.complete);

      await tap.dispose();
      await ended.future;
      yse.Bus.publish('phi.ctl.var.section', const yse.BusString('b'));
      await flush();
      expect(received, isEmpty);
    },
  );
}
