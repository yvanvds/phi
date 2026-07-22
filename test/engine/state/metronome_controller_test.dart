import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_registry.dart';
import 'package:phi/engine/state/metronome_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_synth_gateway.dart';

void main() {
  group('MetronomeController — click session on a domain (#262)', () {
    late FakeMidiGateway gateway;
    var registry = TimeDomainRegistry(const [
      TimeDomain(name: 'drum', tempo: 120),
      TimeDomain(name: 'pad', tempo: 60),
    ]);

    MetronomeController build({
      String? domainName,
      double sessionTempo = 100,
      int beatsPerBar = 4,
      bool accentDownbeat = true,
      double volume = 1.0,
    }) => MetronomeController(
      gateway: gateway,
      domains: () => registry,
      sessionTempo: () => sessionTempo,
      domainName: domainName,
      beatsPerBar: beatsPerBar,
      accentDownbeat: accentDownbeat,
      volume: volume,
    );

    setUp(() {
      gateway = FakeMidiGateway();
      registry = TimeDomainRegistry(const [
        TimeDomain(name: 'drum', tempo: 120),
        TimeDomain(name: 'pad', tempo: 60),
      ]);
    });

    test('starts silent — no transport until enabled', () {
      final controller = build();
      expect(controller.enabled, isFalse);
      expect(gateway.transport, isNull);
      controller.dispose();
    });

    test('enabling mints a transport, plays, and pushes the click pattern', () {
      final controller = build(domainName: 'drum', beatsPerBar: 4);
      controller.setEnabled(true);

      final t = gateway.transport;
      expect(t, isNotNull);
      expect(t!.clockName, MetronomeController.defaultClockName);
      expect(t.isPlaying, isTrue);
      // One-bar loop of one click per beat.
      expect(t.loopBeats, 4);
      expect(t.events, hasLength(4));
      expect(t.events.map((e) => e.startBeat).toList(), [0.0, 1.0, 2.0, 3.0]);
      expect(
        t.events.every((e) => e.channel == MetronomeController.clickChannel),
        isTrue,
      );
      // The downbeat is a distinct, louder click.
      final down = t.events.first;
      final rest = t.events[1];
      expect(down.velocity, greaterThan(rest.velocity));
      expect(down.pitch, isNot(rest.pitch));

      controller.dispose();
    });

    test('disabling stops the click', () {
      final controller = build(domainName: 'drum');
      controller.setEnabled(true);
      final t = gateway.transport!;
      expect(t.isPlaying, isTrue);

      controller.setEnabled(false);
      expect(controller.enabled, isFalse);
      expect(t.isPlaying, isFalse);

      controller.dispose();
    });

    test(
      'paces from the bound domain tempo; session tempo when none bound',
      () {
        final bound = build(domainName: 'drum');
        bound.setEnabled(true);
        expect(gateway.transport!.tempo, 120);
        bound.dispose();

        gateway = FakeMidiGateway();
        final unbound = build(domainName: null, sessionTempo: 100);
        unbound.setEnabled(true);
        expect(gateway.transport!.tempo, 100);
        unbound.dispose();
      },
    );

    test('switching the bound domain re-paces the running click', () {
      fakeAsync((async) {
        final controller = build(domainName: 'drum'); // 120 bpm
        controller.setEnabled(true);
        final t = gateway.transport!;
        expect(t.tempo, 120);

        // At 120 bpm, one second is two beats.
        async.elapse(const Duration(seconds: 1));
        expect(t.beatPosition, closeTo(2.0, 1e-6));

        // Switch to pad @ 60 bpm — the clock re-paces, the beat integral stays
        // continuous, and the note list is never re-pushed.
        final pushesBefore = t.pushCount;
        controller.domainName = 'pad';
        expect(t.tempo, 60);
        expect(t.pushCount, pushesBefore);

        // The next second adds only one beat at the slower rate.
        async.elapse(const Duration(seconds: 1));
        expect(t.beatPosition, closeTo(3.0, 1e-6));

        controller.dispose();
      });
    });

    test('a tempo change on the bound domain re-paces the click', () {
      fakeAsync((async) {
        registry = TimeDomainRegistry(const [
          TimeDomain(name: 'drum', tempo: 120),
        ]);
        final controller = build(domainName: 'drum');
        controller.setEnabled(true);
        final t = gateway.transport!;
        expect(t.tempo, 120);
        async.elapse(const Duration(seconds: 1));
        expect(t.beatPosition, closeTo(2.0, 1e-6));

        // Domains are immutable values, so a tempo edit is a fresh registry; the
        // engine calls refreshDomains after re-binding it.
        registry = TimeDomainRegistry(const [
          TimeDomain(name: 'drum', tempo: 60),
        ]);
        controller.refreshDomains();
        expect(t.tempo, 60);

        async.elapse(const Duration(seconds: 1));
        expect(t.beatPosition, closeTo(3.0, 1e-6));

        controller.dispose();
      });
    });

    test('a vanished bound domain falls back to the session tempo', () {
      final controller = build(domainName: 'drum', sessionTempo: 90);
      controller.setEnabled(true);
      expect(gateway.transport!.tempo, 120);

      // The project no longer defines `drum`.
      registry = TimeDomainRegistry(const []);
      controller.refreshDomains();
      expect(gateway.transport!.tempo, 90);
      expect(controller.boundDomain, isNull);

      controller.dispose();
    });

    test('changing the meter re-pushes the pattern and loop length live', () {
      final controller = build(domainName: 'drum', beatsPerBar: 4);
      controller.setEnabled(true);
      final t = gateway.transport!;
      final pushesBefore = t.pushCount;

      controller.beatsPerBar = 3;
      expect(t.loopBeats, 3);
      expect(t.events, hasLength(3));
      expect(t.pushCount, greaterThan(pushesBefore));

      // A meter below 1 clamps.
      controller.beatsPerBar = 0;
      expect(controller.beatsPerBar, 1);
      expect(t.loopBeats, 1);

      controller.dispose();
    });

    test('toggling the accent re-pushes; off makes every click equal', () {
      final controller = build(domainName: 'drum', beatsPerBar: 4);
      controller.setEnabled(true);
      final t = gateway.transport!;

      controller.accentDownbeat = false;
      final vels = t.events.map((e) => e.velocity).toSet();
      expect(vels, hasLength(1), reason: 'no accent → every click equal');

      controller.dispose();
    });

    test('volume scales click velocities and re-pushes', () {
      final controller = build(domainName: 'drum', volume: 1.0);
      controller.setEnabled(true);
      final t = gateway.transport!;
      final full = t.events.first.velocity;

      controller.volume = 0.5;
      expect(controller.volume, 0.5);
      expect(t.events.first.velocity, closeTo(full * 0.5, 1e-9));

      controller.dispose();
    });

    test('connects the click voice while running, disconnects on stop', () {
      final synthGateway = FakeSynthGateway();
      final synth = synthGateway.materialiseSynth(
        const SineSynth(),
        channel: MetronomeController.clickSynthChannel,
      );
      final controller = MetronomeController(
        gateway: gateway,
        domains: () => registry,
        sessionTempo: () => 120,
        domainName: 'drum',
        clickSynth: () => synth,
      );

      controller.setEnabled(true);
      final t = gateway.transport!;
      expect(t.connectedSynths, contains(synth));

      controller.setEnabled(false);
      expect(t.connectedSynths, isEmpty);

      controller.dispose();
    });

    test('toggle flips enabled and notifies', () {
      final controller = build(domainName: 'drum');
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.toggle();
      expect(controller.enabled, isTrue);
      controller.toggle();
      expect(controller.enabled, isFalse);
      expect(notifications, greaterThanOrEqualTo(2));

      controller.dispose();
    });

    test('exposes the registry domains for the picker', () {
      final controller = build(domainName: 'drum');
      expect(controller.availableDomains.map((d) => d.name), ['drum', 'pad']);
      expect(controller.boundDomain?.tempo, 120);
      controller.dispose();
    });
  });

  group('MetronomeController — state-applied domain tempo overrides (#331)', () {
    late FakeMidiGateway gateway;
    late Map<String, double> overrides;
    var registry = TimeDomainRegistry(const [
      TimeDomain(name: 'drum', tempo: 120),
      TimeDomain(name: 'pad', tempo: 60),
    ]);

    MetronomeController build({
      String? domainName,
      double sessionTempo = 100,
    }) => MetronomeController(
      gateway: gateway,
      domains: () => registry,
      sessionTempo: () => sessionTempo,
      domainTempoOverride: (name) => overrides[name],
      domainName: domainName,
    );

    setUp(() {
      gateway = FakeMidiGateway();
      overrides = {};
      registry = TimeDomainRegistry(const [
        TimeDomain(name: 'drum', tempo: 120),
        TimeDomain(name: 'pad', tempo: 60),
      ]);
    });

    test('a state override on the bound domain re-paces the running click', () {
      final controller = build(domainName: 'drum'); // authored 120
      controller.setEnabled(true);
      final t = gateway.transport!;
      expect(t.tempo, 120, reason: 'starts on the authored domain tempo');

      // A state application lays a live tempo override over `drum`; the engine
      // re-paces the click.
      overrides['drum'] = 90;
      controller.applyTempo();
      expect(t.tempo, 90, reason: 'the click tracks the applied override');

      // The authored payload is untouched — the picker still reads 120.
      expect(controller.boundDomain?.tempo, 120);

      controller.dispose();
    });

    test(
      'the override wins over the authored tempo when starting the click',
      () {
        overrides['drum'] = 75;
        final controller = build(domainName: 'drum'); // authored 120
        controller.setEnabled(true);
        // Enabling mints the transport at the base tempo — already the override.
        expect(gateway.transport!.tempo, 75);
        controller.dispose();
      },
    );

    test('clearing the overrides falls back to the authored tempo', () {
      overrides['drum'] = 90;
      final controller = build(domainName: 'drum');
      controller.setEnabled(true);
      expect(gateway.transport!.tempo, 90);

      // A project swap clears every live override; the engine refreshes the
      // metronome, which re-paces to the authored domain tempo.
      overrides.clear();
      controller.refreshDomains();
      expect(gateway.transport!.tempo, 120);

      controller.dispose();
    });

    test('an override on a different domain never re-paces the click', () {
      final controller = build(domainName: 'drum');
      controller.setEnabled(true);
      final t = gateway.transport!;
      final pushesBefore = t.pushCount;

      // A state re-tempos `pad`, not the bound `drum` — the click holds.
      overrides['pad'] = 200;
      controller.applyTempo();
      expect(t.tempo, 120);
      expect(t.pushCount, pushesBefore, reason: 're-pacing never re-pushes');

      controller.dispose();
    });

    test('with no domain bound, an override is ignored (session tempo)', () {
      overrides['drum'] = 90;
      final controller = build(domainName: null, sessionTempo: 100);
      controller.setEnabled(true);
      // The click paces from the session tempo — no bound domain to override.
      expect(gateway.transport!.tempo, 100);
      controller.dispose();
    });
  });
}
