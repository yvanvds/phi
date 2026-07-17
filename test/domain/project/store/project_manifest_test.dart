import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/store/project_manifest.dart';

void main() {
  group('ProjectManifest', () {
    test('round-trips through JSON', () {
      const manifest = ProjectManifest(
        name: 'my_set',
        tempo: 124,
        sceneName: 'intro',
      );
      final restored = ProjectManifest.fromJson(manifest.toJson());
      expect(restored, manifest);
      expect(restored.formatVersion, ProjectManifest.currentFormatVersion);
    });

    test('defaults fill in for a sparse map', () {
      final manifest = ProjectManifest.fromJson(const {'name': 'bare'});
      expect(manifest.name, 'bare');
      expect(manifest.formatVersion, ProjectManifest.currentFormatVersion);
      expect(manifest.tempo, 120);
      expect(manifest.sceneName, 'untitled');
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
    });
  });
}
