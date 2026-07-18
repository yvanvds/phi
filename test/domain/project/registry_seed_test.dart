import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/time_domains/time_domain.dart';

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
      expect(document.source.name, 'phrase A');
      expect(document.source.notes, isNotEmpty);
      // The default demo chain persists alongside the source notes (issue #135).
      expect(document.chain, isNotEmpty);
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
  });
}
