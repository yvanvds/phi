import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/bridge/clip_control_port.dart';
import 'package:phi/engine/bridge/control_plane_dispatcher.dart';
import 'package:phi/engine/bridge/fx_control_port.dart';
import 'package:phi/engine/bridge/state_control_port.dart';
import 'package:phi/engine/bridge/tempo_control_port.dart';
import 'package:phi/engine/bridge/variable_control_port.dart';
import 'package:phi/engine/bridge/voice_control_port.dart';
import 'package:phi/engine/engine.dart';

import '../test/engine/test_doubles/fake_bus_tap.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end walk for the host-mediated **fx param plane** (issue #316): the
/// exact frame `fx.reverb.mix = 0.25` publishes (proven byte-for-byte by the
/// `phi` library's Python suite — `python/tests/test_verbs.py::FxVerbTest` →
/// `('phi.ctl.fx.reverb.mix', 0.25)`) rides the engine's real bus-tap seam into
/// the real [ControlPlaneDispatcher] and out to the owning [FxControlPort].
///
/// The tap itself is faked (the C API is a pending engine dependency, design
/// `docs/design/live-coding.md` §9), but every seam past it is real: the same
/// [FakeBusTap] the [PhiEngine] holds carries the publish through the live
/// `phi.ctl` broadcast stream to the dispatcher's real subscription, which
/// decodes the fx address, the trailing param, and the numeric value. The fx
/// controller is a recording double — the real fx-registry adapter lands with
/// that epic — so this proves the *dispatch path*, exactly as the sibling
/// state walk proves the state path.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a phi.ctl.fx param set rides the engine tap into the fx '
      'controller, and a non-numeric set degrades to a notice', (tester) async {
    final busTap = FakeBusTap();
    final engine = PhiEngine(FakeYseGateway(), busTap: busTap);

    final notices = <String>[];
    final fx = _RecordingFx();
    final dispatcher = ControlPlaneDispatcher(
      busTap: busTap,
      clips: _inert,
      voices: _inert,
      variables: _inert,
      states: _inert,
      tempo: _inert,
      fx: fx,
      onNotice: notices.add,
    );
    addTearDown(dispatcher.dispose);

    // ── The set rides the engine's tap all the way to the fx controller ──────
    busTap.publish('phi.ctl.fx.reverb.mix', const BusFloat(0.25));
    await tester.pumpAndSettle();

    expect(fx.sets, [(EntityAddress.parse('fx.reverb'), 'mix', 0.25)]);
    expect(notices, isEmpty);

    // ── A non-numeric value degrades gracefully — a notice, never a route ────
    busTap.publish('phi.ctl.fx.reverb.mix', const BusString('loud'));
    await tester.pumpAndSettle();

    expect(fx.sets, hasLength(1)); // still just the one good set
    expect(notices.single, contains('expected a number'));

    await dispatcher.dispose();
    await busTap.dispose();
    await engine.dispose();
  });
}

/// Records the fx-param sets the dispatcher routes — the recording end of the
/// control plane's fx port.
class _RecordingFx implements FxControlPort {
  final List<(EntityAddress, String, double)> sets = [];

  @override
  void setParam(EntityAddress fx, String param, double value) =>
      sets.add((fx, param, value));
}

final _InertPorts _inert = _InertPorts();

/// The control plane's other owning controllers, inert: this walk routes only
/// fx sets, so any call onto another port would surface through the notice log
/// instead of being silently accepted.
class _InertPorts
    implements
        ClipControlPort,
        VoiceControlPort,
        VariableControlPort,
        StateControlPort,
        TempoControlPort {
  @override
  void play(EntityAddress target) {}

  @override
  void stop(EntityAddress target) {}

  @override
  void pause(EntityAddress target) {}

  @override
  void loop(EntityAddress target, {required bool on}) {}

  @override
  void stopAll() {}

  @override
  void note(EntityAddress voice, {required int pitch, int velocity = 100}) {}

  @override
  void off(EntityAddress voice, {int? pitch}) {}

  @override
  void set(String name, Object? value) {}

  @override
  void fire(EntityAddress? machine, String target) {}

  @override
  void setTempo(EntityAddress domain, double bpm) {}
}
