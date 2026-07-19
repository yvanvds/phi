import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/synth/synth_definition.dart';
import 'package:phi/domain/synth/synth_kind.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/domain/voice/voice_kind.dart';

void main() {
  group('seedDefaultProject', () {
    test('creates the demo clip as clip.phrase_a with source + chain', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);

      seedDefaultProject(registry);

      final clip = registry.entityAt(EntityAddress.parse('clip.phrase_a'));
      expect(clip, isNotNull);
      // The payload is now a whole ClipDocument (source + interpretation), kept
      // map-native like the mix strips.
      final payload = clip!.payload! as Map<String, Object?>;
      final document = ClipDocument.fromJson(payload);
      expect(document.source.notes, isNotEmpty);
      // The default demo chain persists alongside the source notes (issue #135).
      expect(document.chain, isNotEmpty);
      // A fresh seed carries the loop flag on and no display name (issue #184).
      expect(document.loop, isTrue);
      expect(payload['source'], isA<Map<String, Object?>>());
      expect((payload['source']! as Map).containsKey('name'), isFalse);
    });

    test('creates the demo time domains under the domain namespace', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);

      seedDefaultProject(registry);

      final drum = registry.entityAt(EntityAddress.parse('domain.drum'));
      expect(drum, isNotNull);
      expect(drum!.payload, isA<TimeDomain>());
      expect((drum.payload! as TimeDomain).tempo, 124);
    });

    test('does not seed any mix channels (fresh project has only master)', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);

      seedDefaultProject(registry);

      expect(registry.childrenOfKind('mix'), isEmpty);
    });

    test('seeds the default voice → synth.sine → master (#205)', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);

      seedDefaultProject(registry);

      // The zero-config starter synth.
      final synth = registry.entityAt(EntityAddress.parse('synth.sine'));
      expect(synth, isNotNull);
      final synthPayload = synth!.payload! as Map<String, Object?>;
      expect(SynthDefinition.fromJson(synthPayload).kind, SynthKind.sine);

      // The default voice binds that synth to the master bus.
      final voice = registry.entityAt(EntityAddress.parse('voice.default'));
      expect(voice, isNotNull);
      final definition = VoiceDefinition.fromJson(
        voice!.payload! as Map<String, Object?>,
      );
      expect(definition.kind, VoiceKind.internal);
      expect(definition.synth, EntityAddress.parse('synth.sine'));
      expect(definition.output, EntityAddress.parse('mix.master'));
    });
  });
}
