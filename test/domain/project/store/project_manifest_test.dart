import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/store/project_manifest.dart';

void main() {
  group('ProjectManifest', () {
    test('round-trips through JSON', () {
      const manifest = ProjectManifest(
        name: 'my_set',
        tempo: 124,
        sceneName: 'intro',
        masterVolume: 0.6,
        masterMuted: true,
      );
      final restored = ProjectManifest.fromJson(manifest.toJson());
      expect(restored, manifest);
      expect(restored.formatVersion, ProjectManifest.currentFormatVersion);
    });

    test('master volume/mute survive the JSON round-trip', () {
      const manifest = ProjectManifest(
        name: 'x',
        masterVolume: 0.33,
        masterMuted: true,
      );
      final restored = ProjectManifest.fromJson(manifest.toJson());
      expect(restored.masterVolume, closeTo(0.33, 1e-9));
      expect(restored.masterMuted, isTrue);
    });

    test('defaults fill in for a sparse map', () {
      final manifest = ProjectManifest.fromJson(const {'name': 'bare'});
      expect(manifest.name, 'bare');
      expect(manifest.formatVersion, ProjectManifest.currentFormatVersion);
      expect(manifest.tempo, 120);
      expect(manifest.sceneName, 'untitled');
      // Master defaults: a fresh/older project's master is at unity, unmuted.
      expect(manifest.masterVolume, 1.0);
      expect(manifest.masterMuted, isFalse);
    });

    test('accepts an integer tempo from a hand-edited file', () {
      final manifest = ProjectManifest.fromJson(const {
        'name': 'x',
        'tempo': 90,
      });
      expect(manifest.tempo, 90.0);
    });

    test('value equality distinguishes every field', () {
      const base = ProjectManifest(name: 'a', tempo: 120, sceneName: 's');
      expect(
        base,
        const ProjectManifest(name: 'a', tempo: 120, sceneName: 's'),
      );
      expect(
        base == const ProjectManifest(name: 'b', tempo: 120, sceneName: 's'),
        isFalse,
      );
      expect(
        base == const ProjectManifest(name: 'a', tempo: 121, sceneName: 's'),
        isFalse,
      );
      expect(
        base ==
            const ProjectManifest(
              name: 'a',
              tempo: 120,
              sceneName: 's',
              masterVolume: 0.5,
            ),
        isFalse,
      );
      expect(
        base ==
            const ProjectManifest(
              name: 'a',
              tempo: 120,
              sceneName: 's',
              masterMuted: true,
            ),
        isFalse,
      );
    });
  });
}
