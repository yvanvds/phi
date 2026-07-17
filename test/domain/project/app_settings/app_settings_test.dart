import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('defaults to no recents and a 60 s autosave cadence', () {
      const settings = AppSettings();
      expect(settings.recentProjects, isEmpty);
      expect(settings.autosaveInterval, const Duration(seconds: 60));
    });

    test('withRecentProject prepends and de-duplicates (moves to front)', () {
      const settings = AppSettings(recentProjects: ['a.phi', 'b.phi']);
      final next = settings.withRecentProject('b.phi');
      expect(next.recentProjects, ['b.phi', 'a.phi']);
    });

    test('withRecentProject caps the list at maxRecentProjects', () {
      final many = [
        for (var i = 0; i < AppSettings.maxRecentProjects; i++) 'p$i.phi',
      ];
      final settings = AppSettings(recentProjects: many);
      final next = settings.withRecentProject('new.phi');
      expect(next.recentProjects.length, AppSettings.maxRecentProjects);
      expect(next.recentProjects.first, 'new.phi');
      // The oldest entry was dropped.
      expect(next.recentProjects, isNot(contains('p9.phi')));
    });

    test('withoutRecentProject drops a dead path', () {
      const settings = AppSettings(recentProjects: ['a.phi', 'b.phi']);
      expect(settings.withoutRecentProject('a.phi').recentProjects, ['b.phi']);
    });

    test('round-trips through JSON', () {
      const settings = AppSettings(
        recentProjects: ['x.phi', 'y.phi'],
        autosaveInterval: Duration(seconds: 30),
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored, settings);
    });

    test('fromJson tolerates missing/invalid keys with defaults', () {
      final restored = AppSettings.fromJson(const {'autosaveSeconds': 0});
      expect(restored.recentProjects, isEmpty);
      // A non-positive cadence falls back to the default.
      expect(restored.autosaveInterval, AppSettings.defaultAutosaveInterval);
    });

    test('value equality and hashCode by fields', () {
      const a = AppSettings(recentProjects: ['a.phi']);
      const b = AppSettings(recentProjects: ['a.phi']);
      const c = AppSettings(recentProjects: ['b.phi']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
