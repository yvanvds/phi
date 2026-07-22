import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/engine/state/state_application_notice.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/engine/state/state_trigger_scheduler.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_midi_transport.dart';

/// The trigger behaviour of design `state-graph.md` §5 (issue #244): timed
/// schedules counting on domain-paced clocks with cancellation on early exit,
/// variable watchers firing on change (never on an already-matching value),
/// the code-fire seam, and the deleted-target guard rail.
void main() {
  late StateMachineController controller;
  late FakeMidiGateway gateway;
  late RuntimeVariableRegistry variables;
  late Map<String, double> tempos;
  late List<StateApplicationNotice> notices;
  late StateTriggerScheduler scheduler;
  late EntityAddress a;
  late EntityAddress b;
  late EntityAddress c;

  final drum = EntityAddress.parse('domain.drum');

  setUp(() {
    controller = StateMachineController();
    gateway = FakeMidiGateway();
    variables = RuntimeVariableRegistry();
    tempos = {'drum': 120};
    notices = [];
    scheduler = StateTriggerScheduler(
      stateMachine: controller,
      variables: variables,
      createTransport: ({required String clockName, required double tempo}) =>
          gateway.createTransport(clockName: clockName, tempo: tempo),
      domainTempo: (domain) => tempos[domain.name],
      onNotice: notices.add,
    );
    // The engine chains entry + move beside the application engine; a bare
    // test wires the seams directly.
    controller.onStateEntered = scheduler.onStateEntered;
    controller.onStateMoved = scheduler.onStateMoved;
    a = controller.addState(name: 'a', position: const Offset(0, 0));
    b = controller.addState(name: 'b', position: const Offset(200, 0));
    c = controller.addState(name: 'c', position: const Offset(400, 0));
  });

  tearDown(() {
    scheduler.dispose();
    controller.dispose();
    variables.dispose();
  });

  /// Make [state] the live state through an explicit *entry* (the passive
  /// boot seed is not one — design §8 decision 2).
  void enter(EntityAddress state) {
    if (controller.activeStateAddress == state) {
      final other = state == a ? b : a;
      controller.setLive(other);
    }
    controller.setLive(state);
  }

  FakeMidiTransport timedClockFor(EntityAddress target) {
    final name = '${StateTriggerScheduler.timedClockPrefix}.${target.format()}';
    final clock = gateway.transports
        .where((t) => t.clockName == name)
        .lastOrNull;
    expect(clock, isNotNull, reason: 'a timed clock should exist for $target');
    return clock!;
  }

  group('timed triggers (N beats on the domain clock)', () {
    // At 120 BPM one beat is 500ms — 2 beats fire at 1s after entry.

    test('fires N beats after the source state is entered', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 2, domain: drum));
        enter(a);

        final clock = timedClockFor(b);
        expect(clock.isPlaying, isTrue);
        expect(clock.tempo, 120);
        expect(scheduler.armedTimedTargets, [b]);

        async.elapse(const Duration(milliseconds: 900));
        expect(controller.activeStateAddress, a, reason: 'not yet 2 beats');

        async.elapse(const Duration(milliseconds: 200));
        expect(controller.activeStateAddress, b);
        expect(notices, isEmpty);
      });
    });

    test('a passively seeded live state does not arm — only an entry does', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 1, domain: drum));
        // `a` is live from the boot seed but was never *entered*.
        expect(controller.activeStateAddress, a);
        expect(scheduler.armedTimedTargets, isEmpty);

        async.elapse(const Duration(seconds: 5));
        expect(controller.activeStateAddress, a);
      });
    });

    test('is cancelled when the source state is left early', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 2, domain: drum));
        enter(a);
        final clock = timedClockFor(b);

        async.elapse(const Duration(milliseconds: 500));
        enter(c); // leave `a` before the 2 beats are up
        expect(clock.isPlaying, isFalse);
        expect(scheduler.armedTimedTargets, isEmpty);

        async.elapse(const Duration(seconds: 5));
        expect(controller.activeStateAddress, c, reason: 'nothing fired late');
      });
    });

    test('re-paces mid-count when the domain tempo moves', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 2, domain: drum));
        enter(a);

        // Half a beat at 120, then the domain doubles to 240: the remaining
        // 1.5 beats take 375ms, so the fire lands near 625ms — well before
        // the 1s it would have taken at 120.
        async.elapse(const Duration(milliseconds: 250));
        tempos['drum'] = 240;
        async.elapse(const Duration(milliseconds: 450));
        expect(controller.activeStateAddress, b);
        expect(timedClockFor(b).tempo, 240);
      });
    });

    test('a deleted target no-ops with a notice (guard rail)', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 1, domain: drum));
        enter(a);

        // An *external* removal (undo / journal replay) leaves `a`'s spec
        // dangling — the interactive delete would have cleared it.
        controller.registry.remove(b);
        async.elapse(const Duration(seconds: 2));

        expect(controller.activeStateAddress, a);
        expect(notices, hasLength(1));
        expect(notices.single.state, a);
        expect(notices.single.message, contains('target deleted'));
        expect(notices.single.message, contains('state.b'));
      });
    });

    test('rename mid-count keeps the count — source and target follow', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 2, domain: drum));
        enter(a);

        async.elapse(const Duration(milliseconds: 500));
        final alpha = controller.rename(a, 'alpha')!;
        final beta = controller.rename(b, 'beta')!;
        expect(scheduler.armedTimedTargets, [beta]);

        // 500ms already counted — only the remaining ~1 beat elapses.
        async.elapse(const Duration(milliseconds: 600));
        expect(controller.activeStateAddress, beta);
        expect(controller.activeStateAddress, isNot(alpha));
        expect(notices, isEmpty);
      });
    });

    test('editing the live entered state\'s trigger arms and cancels in '
        'place', () {
      fakeAsync((async) {
        controller.connect(a, b);
        enter(a);
        expect(scheduler.armedTimedTargets, isEmpty);

        // Manual → timed while `a` is live-and-entered: arms without re-entry.
        controller.setTrigger(a, b, TimedTrigger(beats: 2, domain: drum));
        expect(scheduler.armedTimedTargets, [b]);
        final clock = timedClockFor(b);
        expect(clock.isPlaying, isTrue);

        // Timed → manual: the schedule cancels.
        controller.setTrigger(a, b, const ManualTrigger());
        expect(scheduler.armedTimedTargets, isEmpty);
        expect(clock.isPlaying, isFalse);

        async.elapse(const Duration(seconds: 5));
        expect(controller.activeStateAddress, a);
      });
    });

    test('cancelAll drops every schedule (the project-swap seam)', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 1, domain: drum));
        enter(a);
        expect(scheduler.armedTimedTargets, [b]);

        scheduler.cancelAll();
        expect(scheduler.armedTimedTargets, isEmpty);
        async.elapse(const Duration(seconds: 5));
        expect(controller.activeStateAddress, a);
      });
    });

    test('degrades to a notice without a clock source', () {
      fakeAsync((async) {
        final bare = StateTriggerScheduler(
          stateMachine: controller,
          domainTempo: (domain) => tempos[domain.name],
          onNotice: notices.add,
        );
        controller.onStateEntered = bare.onStateEntered;
        controller.connect(a, b);
        controller.setTrigger(a, b, TimedTrigger(beats: 1, domain: drum));
        enter(a);

        expect(bare.armedTimedTargets, isEmpty);
        expect(notices.single.message, contains('no clock source'));
        async.elapse(const Duration(seconds: 2));
        expect(controller.activeStateAddress, a);
        bare.dispose();
      });
    });

    test('degrades to a notice when the domain is missing', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.setTrigger(
          a,
          b,
          TimedTrigger(beats: 1, domain: EntityAddress.parse('domain.gone')),
        );
        enter(a);

        expect(scheduler.armedTimedTargets, isEmpty);
        expect(notices.single.state, a);
        expect(notices.single.message, contains('domain.gone'));
        async.elapse(const Duration(seconds: 2));
        expect(controller.activeStateAddress, a);
      });
    });
  });

  group('variable triggers (checked on change, not polled)', () {
    test('fires when the watched variable changes to the match value', () {
      variables.define(name: 'section', values: ['a', 'b'], current: 'a');
      controller.connect(a, b);
      controller.setTrigger(
        a,
        b,
        const VariableTrigger(name: 'section', value: 'b'),
      );

      variables.setValue('section', 'b');
      expect(controller.activeStateAddress, b);
      expect(notices, isEmpty);
    });

    test('a value already matching when the watcher arms does not fire', () {
      variables.define(name: 'section', values: ['a', 'b'], current: 'a');
      controller.connect(a, b);
      controller.setTrigger(
        a,
        b,
        const VariableTrigger(name: 'section', value: 'a'),
      );

      // Nothing changed *onto* the match value — an unrelated mutation must
      // not fire the already-matching watcher.
      variables.define(name: 'mode', values: ['x', 'y'], current: 'x');
      variables.setValue('mode', 'y');
      expect(controller.activeStateAddress, a);
    });

    test('an unrelated variable change does not fire', () {
      variables.define(name: 'section', values: ['a', 'b'], current: 'a');
      variables.define(name: 'mode', values: ['x', 'y'], current: 'x');
      controller.connect(a, b);
      controller.setTrigger(
        a,
        b,
        const VariableTrigger(name: 'section', value: 'b'),
      );

      variables.setValue('mode', 'y');
      expect(controller.activeStateAddress, a);
    });

    test('a change to a non-matching value does not fire', () {
      variables.define(name: 'section', values: ['a', 'b', 'c'], current: 'a');
      controller.connect(a, b);
      controller.setTrigger(
        a,
        b,
        const VariableTrigger(name: 'section', value: 'b'),
      );

      variables.setValue('section', 'c');
      expect(controller.activeStateAddress, a);
    });

    test('only the live state\'s watchers are armed', () {
      // The transition rides `b`, not the live `a` — moving the variable
      // must not fire it.
      controller.connect(b, c);
      controller.setTrigger(
        b,
        c,
        const VariableTrigger(name: 'section', value: 'go'),
      );
      variables.define(name: 'section', values: ['stop', 'go']);

      variables.setValue('section', 'go');
      expect(controller.activeStateAddress, a);

      // Once `b` is live, the next change *onto* the value fires.
      variables.setValue('section', 'stop');
      enter(b);
      variables.setValue('section', 'go');
      expect(controller.activeStateAddress, c);
    });

    test('the first matching transition in payload order wins', () {
      controller.connect(a, b);
      controller.connect(a, c);
      controller.setTrigger(a, b, const VariableTrigger(name: 'x', value: '1'));
      controller.setTrigger(a, c, const VariableTrigger(name: 'x', value: '1'));
      variables.define(name: 'x', values: ['0', '1'], current: '0');

      variables.setValue('x', '1');
      expect(controller.activeStateAddress, b);
    });

    test('a deleted target no-ops with a notice (guard rail)', () {
      controller.connect(a, b);
      controller.setTrigger(
        a,
        b,
        const VariableTrigger(name: 'section', value: 'b'),
      );
      variables.define(name: 'section', values: ['a', 'b'], current: 'a');
      controller.registry.remove(b); // external — the spec stays, dangling

      variables.setValue('section', 'b');
      expect(controller.activeStateAddress, a);
      expect(notices.single.message, contains('target deleted'));
    });
  });

  group('code trigger — fireTo (the phi control-plane seam)', () {
    test('fires the live state\'s transition toward the named state', () {
      controller.connect(a, b);
      expect(scheduler.fireTo('b'), isTrue);
      expect(controller.activeStateAddress, b);
    });

    test('resolves dotted and fully-qualified names too', () {
      controller.connect(a, b);
      expect(scheduler.fireTo('state.b'), isTrue);
      expect(controller.activeStateAddress, b);
    });

    test('no matching transition degrades to a notice', () {
      controller.connect(a, b);
      expect(scheduler.fireTo('nope'), isFalse);
      expect(controller.activeStateAddress, a);
      expect(notices.single.state, a);
      expect(notices.single.message, contains('no transition'));
    });

    test('a deleted target no-ops with a notice (guard rail)', () {
      controller.connect(a, b);
      controller.registry.remove(b); // external — the spec stays, dangling
      expect(scheduler.fireTo('b'), isFalse);
      expect(controller.activeStateAddress, a);
      expect(notices.single.message, contains('target deleted'));
    });

    test('an entry through fireTo arms the target\'s own timed triggers', () {
      fakeAsync((async) {
        controller.connect(a, b);
        controller.connect(b, c);
        controller.setTrigger(b, c, TimedTrigger(beats: 1, domain: drum));

        expect(scheduler.fireTo('b'), isTrue);
        expect(scheduler.armedTimedTargets, [c]);
        async.elapse(const Duration(milliseconds: 600));
        expect(controller.activeStateAddress, c);
      });
    });
  });
}
