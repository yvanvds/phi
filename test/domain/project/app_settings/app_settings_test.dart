import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/midi_settings.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';

void main() {
  group('AppSettings', () {
    test(
      'defaults to no recents/pins, 60 s autosave, and default sections',
      () {
        const settings = AppSettings();
        expect(settings.recentProjects, isEmpty);
        expect(settings.pinnedProjects, isEmpty);
        expect(settings.autosaveInterval, const Duration(seconds: 60));
        expect(settings.audio, const AudioSettings());
        expect(settings.midi, const MidiSettings());
        expect(settings.version, AppSettings.schemaVersion);
      },
    );

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

    test('withoutRecentProject drops a dead path from recents and pins', () {
      const settings = AppSettings(
        recentProjects: ['a.phi', 'b.phi'],
        pinnedProjects: ['a.phi'],
      );
      final next = settings.withoutRecentProject('a.phi');
      expect(next.recentProjects, ['b.phi']);
      expect(next.pinnedProjects, isEmpty);
    });

    test('round-trips through JSON', () {
      const settings = AppSettings(
        recentProjects: ['x.phi', 'y.phi'],
        pinnedProjects: ['z.phi'],
        autosaveInterval: Duration(seconds: 30),
        audio: AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Fireface UCX',
          sampleRate: 48000,
          bufferSize: 256,
          layout: SpeakerLayout.surround71,
        ),
        midi: MidiSettings(
          outputPort: 'loopMIDI Port',
          inputPorts: ['Keystation 61'],
        ),
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored, settings);
    });

    test('toJson always writes version 1', () {
      expect(const AppSettings().toJson()['version'], 1);
    });

    test('an old settings.json without the new keys loads to defaults', () {
      // A file written before this schema grew: only the original two keys.
      final restored = AppSettings.fromJson(const {
        'recentProjects': ['old.phi'],
        'autosaveSeconds': 45,
      });
      expect(restored.recentProjects, ['old.phi']);
      expect(restored.autosaveInterval, const Duration(seconds: 45));
      // Everything new falls back to defaults.
      expect(restored.pinnedProjects, isEmpty);
      expect(restored.audio, const AudioSettings());
      expect(restored.midi, const MidiSettings());
      expect(restored.version, AppSettings.schemaVersion);
    });

    test('fromJson tolerates missing/invalid keys with defaults', () {
      final restored = AppSettings.fromJson(const {
        'autosaveSeconds': 0,
        'pinnedProjects': 'not-a-list',
        'audio': 'not-a-map',
        'midi': 42,
        'version': -3,
      });
      expect(restored.recentProjects, isEmpty);
      expect(restored.pinnedProjects, isEmpty);
      // A non-positive cadence falls back to the default.
      expect(restored.autosaveInterval, AppSettings.defaultAutosaveInterval);
      expect(restored.audio, const AudioSettings());
      expect(restored.midi, const MidiSettings());
      // A non-positive version falls back to the current schema version.
      expect(restored.version, AppSettings.schemaVersion);
    });

    test('value equality and hashCode by fields', () {
      const a = AppSettings(recentProjects: ['a.phi']);
      const b = AppSettings(recentProjects: ['a.phi']);
      const c = AppSettings(recentProjects: ['b.phi']);
      const d = AppSettings(
        recentProjects: ['a.phi'],
        audio: AudioSettings(outputDevice: 'X'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      // A differing section breaks equality too.
      expect(a, isNot(d));
    });
  });

  group('AppSettings pins', () {
    test('withPinnedProject moves the path out of recents into pins', () {
      const settings = AppSettings(recentProjects: ['a.phi', 'b.phi']);
      final next = settings.withPinnedProject('a.phi');
      expect(next.pinnedProjects, ['a.phi']);
      // No longer duplicated in recents — the File menu lists it once.
      expect(next.recentProjects, ['b.phi']);
    });

    test('withPinnedProject prepends and de-duplicates the pin list', () {
      const settings = AppSettings(pinnedProjects: ['a.phi', 'b.phi']);
      final next = settings.withPinnedProject('b.phi');
      expect(next.pinnedProjects, ['b.phi', 'a.phi']);
    });

    test('a pinned path is never dropped by the recents cap', () {
      var settings = const AppSettings().withPinnedProject('pinned.phi');
      // Churn far more recents than the cap; the pin must survive.
      for (var i = 0; i < AppSettings.maxRecentProjects * 3; i++) {
        settings = settings.withRecentProject('r$i.phi');
      }
      expect(settings.recentProjects.length, AppSettings.maxRecentProjects);
      expect(settings.pinnedProjects, ['pinned.phi']);
      // The pin stays out of the capped recents list.
      expect(settings.recentProjects, isNot(contains('pinned.phi')));
    });

    test(
      'opening a pinned project leaves recents untouched (no duplicate)',
      () {
        const settings = AppSettings(
          recentProjects: ['b.phi'],
          pinnedProjects: ['a.phi'],
        );
        final next = settings.withRecentProject('a.phi');
        expect(next.pinnedProjects, ['a.phi']);
        expect(next.recentProjects, ['b.phi']);
      },
    );

    test('withoutPinnedProject unpins and returns the path to recents', () {
      const settings = AppSettings(
        recentProjects: ['b.phi'],
        pinnedProjects: ['a.phi'],
      );
      final next = settings.withoutPinnedProject('a.phi');
      expect(next.pinnedProjects, isEmpty);
      // Back at the front of recents — an ordinary recent that can age out.
      expect(next.recentProjects, ['a.phi', 'b.phi']);
    });

    test('withoutPinnedProject is a no-op for an unpinned path', () {
      const settings = AppSettings(recentProjects: ['a.phi']);
      expect(settings.withoutPinnedProject('nope.phi'), settings);
    });

    test('pin then unpin restores the path as a recent (round trip)', () {
      const settings = AppSettings(recentProjects: ['a.phi', 'b.phi']);
      final pinned = settings.withPinnedProject('a.phi');
      final unpinned = pinned.withoutPinnedProject('a.phi');
      expect(unpinned.pinnedProjects, isEmpty);
      expect(unpinned.recentProjects, contains('a.phi'));
      expect(unpinned.recentProjects, contains('b.phi'));
    });
  });
}
