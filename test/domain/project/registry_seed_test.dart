import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/time_domains/time_domain.dart';

void main() {
  group('seedDefaultProject', () {
    test('creates the demo clip as clip.phrase_a with its source payload', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);

      seedDefaultProject(registry);

      final clip = registry.entityAt(EntityAddress.parse('clip.phrase_a'));
      expect(clip, isNotNull);
      final payload = clip!.payload;
      expect(payload, isA<MidiClip>());
      expect((payload! as MidiClip).name, 'phrase A');
      expect((payload as MidiClip).notes, isNotEmpty);
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
