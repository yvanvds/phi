import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/bridge/clip_control_port.dart';
import 'package:phi/engine/bridge/control_plane_dispatcher.dart';
import 'package:phi/engine/bridge/fx_control_port.dart';
import 'package:phi/engine/bridge/state_control_port.dart';
import 'package:phi/engine/bridge/tempo_control_port.dart';
import 'package:phi/engine/bridge/variable_control_port.dart';
import 'package:phi/engine/bridge/voice_control_port.dart';

import '../test_doubles/fake_bus_tap.dart';

/// One recording double standing in for all five owning controllers, so a test
/// can assert exactly which port call a decoded `phi.ctl` frame produced. The
/// [calls] log doubles as a "nothing was routed" probe for degradation tests.
class _RecordingControllers
    implements
        ClipControlPort,
        VoiceControlPort,
        VariableControlPort,
        StateControlPort,
        TempoControlPort,
        FxControlPort {
  final List<String> calls = [];

  final List<EntityAddress> plays = [];
  final List<EntityAddress> stops = [];
  final List<EntityAddress> pauses = [];
  final List<(EntityAddress, bool)> loops = [];
  int stopAlls = 0;

  final List<(EntityAddress, int, int)> notes = [];
  final List<(EntityAddress, int?)> offs = [];

  final List<(String, Object?)> sets = [];
  final List<(EntityAddress?, String)> fires = [];
  final List<(EntityAddress, double)> tempos = [];
  final List<(EntityAddress, String, double)> fxSets = [];

  @override
  void play(EntityAddress target) {
    plays.add(target);
    calls.add('play $target');
  }

  @override
  void stop(EntityAddress target) {
    stops.add(target);
    calls.add('stop $target');
  }

  @override
  void pause(EntityAddress target) {
    pauses.add(target);
    calls.add('pause $target');
  }

  @override
  void loop(EntityAddress target, {required bool on}) {
    loops.add((target, on));
    calls.add('loop $target $on');
  }

  @override
  void stopAll() {
    stopAlls++;
    calls.add('stopAll');
  }

  @override
  void note(EntityAddress voice, {required int pitch, int velocity = 100}) {
    notes.add((voice, pitch, velocity));
    calls.add('note $voice $pitch $velocity');
  }

  @override
  void off(EntityAddress voice, {int? pitch}) {
    offs.add((voice, pitch));
    calls.add('off $voice $pitch');
  }

  @override
  void set(String name, Object? value) {
    sets.add((name, value));
    calls.add('set $name $value');
  }

  @override
  void fire(EntityAddress? machine, String target) {
    fires.add((machine, target));
    calls.add('fire $machine $target');
  }

  @override
  void setTempo(EntityAddress domain, double bpm) {
    tempos.add((domain, bpm));
    calls.add('tempo $domain $bpm');
  }

  @override
  void setParam(EntityAddress fx, String param, double value) {
    fxSets.add((fx, param, value));
    calls.add('fx $fx $param $value');
  }
}

void main() {
  late FakeBusTap tap;
  late _RecordingControllers ctl;
  late List<String> notices;
  late ControlPlaneDispatcher dispatcher;

  setUp(() {
    tap = FakeBusTap();
    ctl = _RecordingControllers();
    notices = [];
    dispatcher = ControlPlaneDispatcher(
      busTap: tap,
      clips: ctl,
      voices: ctl,
      variables: ctl,
      states: ctl,
      tempo: ctl,
      fx: ctl,
      onNotice: notices.add,
    );
  });

  tearDown(() async {
    await dispatcher.dispose();
    await tap.dispose();
  });

  /// Drive one decoded frame synchronously (bypassing the async stream), so the
  /// per-verb dispatch assertions read straightforwardly.
  void send(String address, BusValue value) =>
      dispatcher.handleFrame(BusTapFrame(address, value));

  group('clip verbs', () {
    test('play / stop / pause route to the addressed clip', () {
      send('phi.ctl.clip.drums.intro_fill.play', const BusInt(1));
      send('phi.ctl.clip.drums.intro_fill.stop', const BusInt(1));
      send('phi.ctl.clip.drums.intro_fill.pause', const BusInt(1));

      final clip = EntityAddress.parse('clip.drums.intro_fill');
      expect(ctl.plays, [clip]);
      expect(ctl.stops, [clip]);
      expect(ctl.pauses, [clip]);
      expect(notices, isEmpty);
    });

    test('loop on/off decodes the int flag', () {
      send('phi.ctl.clip.drums.intro_fill.loop', const BusInt(1));
      send('phi.ctl.clip.drums.intro_fill.loop', const BusInt(0));

      final clip = EntityAddress.parse('clip.drums.intro_fill');
      expect(ctl.loops, [(clip, true), (clip, false)]);
    });

    test('a group verb routes the group address (controller resolves it)', () {
      send('phi.ctl.clip.drums.stop', const BusInt(1));
      expect(ctl.stops, [EntityAddress.parse('clip.drums')]);
      expect(ctl.stopAlls, 0);
    });

    test('root stop is stop-all', () {
      send('phi.ctl.clip.stop', const BusInt(1));
      expect(ctl.stopAlls, 1);
      expect(ctl.stops, isEmpty);
    });
  });

  group('voice verbs', () {
    test('note with default and explicit velocity', () {
      send('phi.ctl.voice.bells.note', const BusFloatList([60, 100]));
      send('phi.ctl.voice.bells.note', const BusFloatList([60, 40]));

      final bells = EntityAddress.parse('voice.bells');
      expect(ctl.notes, [(bells, 60, 100), (bells, 60, 40)]);
    });

    test('off a specific pitch, and off-all with an empty list', () {
      send('phi.ctl.voice.bells.off', const BusFloatList([60]));
      send('phi.ctl.voice.bells.off', const BusFloatList([]));

      final bells = EntityAddress.parse('voice.bells');
      expect(ctl.offs, [(bells, 60), (bells, null)]);
    });
  });

  group('var / state / domain verbs', () {
    test('var assignment keeps the value type (string then int)', () {
      send('phi.ctl.var.section', const BusString('b'));
      send('phi.ctl.var.count', const BusInt(3));

      expect(ctl.sets, [('section', 'b'), ('count', 3)]);
    });

    test('state.fire routes the target on the default machine', () {
      send('phi.ctl.state.fire', const BusString('break'));
      expect(ctl.fires, [(null, 'break')]);
    });

    test('state.<machine>.fire names the machine', () {
      send('phi.ctl.state.verse_switch.fire', const BusString('chorus'));
      expect(ctl.fires, [
        (EntityAddress.parse('state.verse_switch'), 'chorus'),
      ]);
    });

    test('domain tempo decodes a float bpm', () {
      send('phi.ctl.domain.drum.tempo', const BusFloat(124));
      expect(ctl.tempos, [(EntityAddress.parse('domain.drum'), 124.0)]);
    });
  });

  group('fx verbs (host-mediated param sets)', () {
    test('a param set routes the fx address, param name, and value', () {
      // The exact frame `fx.reverb.mix = 0.25` publishes (python/tests/
      // test_verbs.py::FxVerbTest → `('phi.ctl.fx.reverb.mix', 0.25)`).
      send('phi.ctl.fx.reverb.mix', const BusFloat(0.25));
      expect(ctl.fxSets, [(EntityAddress.parse('fx.reverb'), 'mix', 0.25)]);
      expect(notices, isEmpty);
    });

    test('an int value coerces to a double (an integral knob)', () {
      send('phi.ctl.fx.big_delay.taps', const BusInt(3));
      expect(ctl.fxSets, [(EntityAddress.parse('fx.big_delay'), 'taps', 3.0)]);
    });

    test('a grouped fx address keeps every segment but the param', () {
      send('phi.ctl.fx.bus.reverb.mix', const BusFloat(0.4));
      expect(ctl.fxSets, [(EntityAddress.parse('fx.bus.reverb'), 'mix', 0.4)]);
    });
  });

  group('graceful degradation (notice, never a crash, never a route)', () {
    test('an unknown namespace is dropped', () {
      // `fx` now routes (see the fx group); an unrecognised namespace still
      // degrades gracefully rather than throwing.
      send('phi.ctl.synth.bells.cutoff', const BusFloat(0.4));
      expect(ctl.calls, isEmpty);
      expect(notices.single, contains('unknown control namespace "synth"'));
    });

    test('an fx set with no param is dropped (bare fx address)', () {
      send('phi.ctl.fx.reverb', const BusFloat(0.4));
      expect(ctl.calls, isEmpty);
      expect(notices.single, contains('needs an fx address and a param'));
    });

    test('an fx param with a non-numeric value is dropped, not routed', () {
      send('phi.ctl.fx.reverb.mix', const BusString('loud'));
      expect(ctl.fxSets, isEmpty);
      expect(notices.single, contains('expected a number'));
    });

    test('the bare prefix carries no command', () {
      send('phi.ctl', const BusInt(1));
      expect(ctl.calls, isEmpty);
      expect(notices, hasLength(1));
    });

    test('an unknown clip verb is dropped', () {
      send('phi.ctl.clip.drums.frobnicate', const BusInt(1));
      expect(ctl.calls, isEmpty);
      expect(notices.single, contains('unknown clip verb "frobnicate"'));
    });

    test('play/pause/loop on the clip root need a target', () {
      send('phi.ctl.clip.play', const BusInt(1));
      send('phi.ctl.clip.pause', const BusInt(1));
      expect(ctl.calls, isEmpty);
      expect(notices, hasLength(2));
    });

    test('a voice verb without a target voice is dropped', () {
      send('phi.ctl.voice.note', const BusFloatList([60]));
      expect(ctl.calls, isEmpty);
      expect(notices.single, contains('needs a target voice'));
    });

    test('note with the wrong value type is dropped, not routed', () {
      send('phi.ctl.voice.bells.note', const BusString('oops'));
      expect(ctl.notes, isEmpty);
      expect(notices.single, contains('float list'));
    });

    test('note with an empty arg list needs a pitch', () {
      send('phi.ctl.voice.bells.note', const BusFloatList([]));
      expect(ctl.notes, isEmpty);
      expect(notices.single, contains('needs a pitch'));
    });

    test('state.fire with a non-string target is dropped', () {
      send('phi.ctl.state.fire', const BusInt(7));
      expect(ctl.fires, isEmpty);
      expect(notices.single, contains('string target'));
    });

    test('a non-tempo domain param is dropped (out of scope)', () {
      send('phi.ctl.domain.drum.swing', const BusFloat(0.2));
      expect(ctl.calls, isEmpty);
      expect(notices.single, contains('not a tempo set'));
    });

    test(
      'an address with an invalid segment degrades rather than throwing',
      () {
        // `Drums` fails NameValidator (uppercase) → EntityAddress throws → the
        // dispatcher's guard turns it into a notice, no crash, no route.
        send('phi.ctl.clip.Drums.play', const BusInt(1));
        expect(ctl.calls, isEmpty);
        expect(notices.single, contains('dropped'));
      },
    );

    test('an empty var name is dropped', () {
      send('phi.ctl.var', const BusString('x'));
      expect(ctl.sets, isEmpty);
      expect(notices, hasLength(1));
    });
  });

  group(
    'end-to-end fake flow (script publish → tap → dispatcher → effect)',
    () {
      test('a publish through the real tap subscription reaches the '
          'controller', () async {
        // No handleFrame shortcut here: the frame travels the exact path
        // production uses — FakeBusTap.publish → the phi.ctl broadcast stream →
        // the dispatcher's subscription → the owning controller.
        tap.publish('phi.ctl.clip.drums.intro_fill.play', const BusInt(1));
        tap.publish('phi.ctl.voice.bells.note', const BusFloatList([60, 100]));
        tap.publish('phi.ctl.var.section', const BusString('b'));
        tap.publish('phi.ctl.fx.reverb.mix', const BusFloat(0.25));

        await pumpEventQueue();

        expect(ctl.plays, [EntityAddress.parse('clip.drums.intro_fill')]);
        expect(ctl.notes, [(EntityAddress.parse('voice.bells'), 60, 100)]);
        expect(ctl.sets, [('section', 'b')]);
        expect(ctl.fxSets, [(EntityAddress.parse('fx.reverb'), 'mix', 0.25)]);
        expect(notices, isEmpty);
      });

      test(
        'publishes outside the phi.ctl prefix never reach the plane',
        () async {
          tap.publish(
            'channel.pads.volume',
            const BusFloat(0.6),
          ); // engine-direct
          tap.publish('phi.ctlx.spoof', const BusInt(9)); // not a segment child

          await pumpEventQueue();

          expect(ctl.calls, isEmpty);
          expect(notices, isEmpty);
        },
      );

      test('dispose stops routing further publishes', () async {
        await dispatcher.dispose();
        tap.publish('phi.ctl.clip.drums.intro_fill.play', const BusInt(1));

        await pumpEventQueue();

        expect(ctl.calls, isEmpty);
      });
    },
  );
}
