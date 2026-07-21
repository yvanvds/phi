import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/metronome_controller.dart';

import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// The metronome's engine wiring (issue #262): `PhiEngine` owns the
/// [MetronomeController], feeds it the project's `domain.` entities, and — only
/// when the click is first enabled — materialises the reserved click voice (a
/// sine synth on the reserved channel, routed to master), connecting the click
/// transport to it. Exercised entirely through the fakes.
void main() {
  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: synths,
      fxGateway: fxs,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  ProjectRegistry registryWithDrum() {
    final registry = ProjectRegistry();
    registry.createEntity(
      EntityAddress(kind: RegistryKinds.domain, segments: const ['drum']),
      payload: const TimeDomain(name: 'drum', tempo: 124),
    );
    return registry;
  }

  test('the bound registry\'s domains reach the metronome picker', () {
    final registry = registryWithDrum();
    addTearDown(registry.dispose);

    engine.start();
    engine.bindProject(registry);

    expect(
      engine.metronome.availableDomains.map((d) => d.name),
      contains('drum'),
    );
  });

  test(
    'enabling the click lazily materialises a reserved sine voice on master',
    () {
      final registry = registryWithDrum();
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final metronome = engine.metronome;

      // Nothing materialised until the click is first enabled — the racks stay
      // untouched for a project that never clicks.
      expect(synths.synths, isEmpty);

      metronome.domainName = 'drum';
      metronome.setEnabled(true);

      // A single reserved click synth, on the reserved channel, bound to master.
      final clickSynth = synths.synths.single;
      expect(clickSynth.channel, MetronomeController.clickSynthChannel);
      expect(clickSynth.boundBus, isNull);

      // The click session runs on its own clock at the bound domain's tempo, its
      // transport connected to that reserved voice.
      final click = midi.transports.firstWhere(
        (t) => t.clockName == MetronomeController.defaultClockName,
      );
      expect(click.tempo, 124);
      expect(click.isPlaying, isTrue);
      expect(click.connectedSynths, contains(clickSynth));

      // Re-enabling does not mint a second click synth (it is cached).
      metronome.setEnabled(false);
      metronome.setEnabled(true);
      expect(synths.synths, hasLength(1));
    },
  );
}
