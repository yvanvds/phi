import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/domain_subscription_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_registry.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// The clock-binding half of a state's tempos slice (issue #243):
/// [EngineMidiController.applyDomainTempo] lays a live per-domain override
/// over the authored `domain.` tempo — journal-free — re-pacing every
/// subscribed session at once, and [clearDomainTempoOverrides] returns the
/// performance to authored tempos on a project swap.
void main() {
  final drum = EntityAddress.parse('domain.drum');

  MidiTransformChain subscribedChain() => MidiTransformChain(
    source: MidiClip(
      bars: 2,
      notes: const [
        MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
      ],
    ),
    transforms: <MidiTransform>[
      DomainSubscriptionTransform.resolve(
        registry: TimeDomainRegistry(const [
          TimeDomain(name: 'drum', tempo: 124),
        ]),
        domainName: 'drum',
        label: 'domain · drum @ 124',
      ),
    ],
  );

  test('applyDomainTempo re-paces a playing subscribed session at once and '
      'clearDomainTempoOverrides restores the authored tempo', () {
    fakeAsync((async) {
      final gateway = FakeMidiGateway();
      final controller = EngineMidiController(
        chain: subscribedChain(),
        gateway: gateway,
      );

      controller.play();
      async.elapse(const Duration(milliseconds: 20));
      expect(gateway.transport!.tempo, 124);

      controller.applyDomainTempo(drum, 100);
      expect(controller.domainTempoOverride('drum'), 100);
      expect(gateway.transport!.tempo, 100);

      controller.clearDomainTempoOverrides();
      expect(controller.domainTempoOverride('drum'), isNull);
      expect(gateway.transport!.tempo, 124);

      controller.stop();
      controller.dispose();
    });
  });

  test('a non-positive bpm is ignored — clocks cannot run backward', () {
    final controller = EngineMidiController(
      chain: subscribedChain(),
      gateway: FakeMidiGateway(),
    );

    controller.applyDomainTempo(drum, 0);
    expect(controller.domainTempoOverride('drum'), isNull);
    controller.applyDomainTempo(drum, -10);
    expect(controller.domainTempoOverride('drum'), isNull);

    controller.dispose();
  });

  test('a session started after the override picks it up on play', () {
    fakeAsync((async) {
      final gateway = FakeMidiGateway();
      final controller = EngineMidiController(
        chain: subscribedChain(),
        gateway: gateway,
      );

      controller.applyDomainTempo(drum, 90);
      controller.play();
      async.elapse(const Duration(milliseconds: 20));

      expect(gateway.transport!.tempo, 90);

      controller.stop();
      controller.dispose();
    });
  });
}
