import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/real_yse_gateway.dart';

/// Holds **libyse itself** to the master-volume contract on [RealYseGateway]
/// (issue #421): a write outside a session is a no-op, not a crash.
///
/// `Channel.master.volume =` reaches `YSE::channel::setVolume()`, which calls
/// `pimpl->sendMessage()` unconditionally — and `System::close()` nulls the
/// master's `pimpl` (there is none before the first init either). The C shim
/// checks only the channel pointer. Unguarded, the second test below takes the
/// whole test process down with a segfault; no test against the fake can show
/// that, because the fake has no `pimpl` to dereference.
///
/// Kept in its own file so that, should the guard ever regress, the crash costs
/// only this file rather than the enumeration contract alongside it. Skips
/// itself where the native library is not loadable, like
/// `real_yse_gateway_enumeration_contract_test.dart`.
void main() {
  late RealYseGateway gateway;
  late bool engineAvailable;

  setUpAll(() {
    gateway = RealYseGateway();
    try {
      gateway.engineVersion;
      engineAvailable = true;
    } catch (_) {
      engineAvailable = false;
    }
  });

  tearDownAll(() {
    if (engineAvailable) {
      try {
        gateway.close();
      } catch (_) {
        // Closing an engine that is not up is not a test failure.
      }
    }
  });

  test('a master volume write before the first init is a no-op', () {
    if (!engineAvailable) {
      markTestSkipped('libyse is not loadable here — contract unchecked');
      return;
    }
    final before = gateway.masterVolume;

    gateway.masterVolume = 0.4;

    expect(gateway.masterVolume, closeTo(before, 1e-6));
  });

  test('a master volume write on a closed engine is a no-op, not a native '
      'crash', () {
    if (!engineAvailable) {
      markTestSkipped('libyse is not loadable here — contract unchecked');
      return;
    }
    gateway.initOffline();
    gateway.masterVolume = 0.3;
    expect(gateway.masterVolume, closeTo(0.3, 1e-6));

    gateway.close();
    // Reaching the next line at all is most of the assertion: unguarded, this
    // write dereferences the master's nulled `pimpl`.
    gateway.masterVolume = 0.7;

    expect(
      gateway.masterVolume,
      closeTo(0.3, 1e-6),
      reason: 'the write while closed must not reach the engine',
    );
  });

  test('a new session accepts master writes again', () {
    if (!engineAvailable) {
      markTestSkipped('libyse is not loadable here — contract unchecked');
      return;
    }
    gateway.initOffline();

    gateway.masterVolume = 0.6;

    expect(gateway.masterVolume, closeTo(0.6, 1e-6));
    gateway.masterVolume = 1.0;
  });
}
