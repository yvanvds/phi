import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/domain/shell_layout/shell_layout.dart';

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

    test('the workspace layout survives the JSON round-trip', () {
      // A two-pane arrangement — Mix beside MIDI — distinct from the seed.
      final arranged = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final manifest = ProjectManifest(name: 'set', layout: arranged);

      final restored = ProjectManifest.fromJson(manifest.toJson());

      expect(restored.layout, arranged);
      expect(restored.layout.paneCount, 2);
      expect(restored.layout.placedSurfaces, {'mix', 'midi'});
    });

    test('layout defaults to the single-pane Mix seed', () {
      const manifest = ProjectManifest(name: 'fresh');
      expect(manifest.layout, ShellLayout.defaultSeed);
      expect(manifest.layout.paneCount, 1);
      expect(manifest.layout.placedSurfaces, {'mix'});
    });

    test('an older, layout-less map falls back to the seed layout', () {
      // No `layout` key — a project saved before issue #253.
      final manifest = ProjectManifest.fromJson(const {'name': 'legacy'});
      expect(manifest.layout, ShellLayout.defaultSeed);
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

    test('value equality distinguishes the layout', () {
      final arranged = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final base = ProjectManifest(name: 'a', layout: arranged);
      expect(base == ProjectManifest(name: 'a', layout: arranged), isTrue);
      // Same everything but the (default, single-pane) layout.
      expect(base == const ProjectManifest(name: 'a'), isFalse);
    });
  });
}
