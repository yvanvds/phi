import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/midi_settings.dart';
import 'package:phi/domain/project/app_settings/real_app_settings_store.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phi_settings_test_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('RealAppSettingsStore', () {
    test('load returns defaults when no settings file exists', () async {
      final store = RealAppSettingsStore(directory: temp);
      expect(await store.load(), const AppSettings());
    });

    test('save then load round-trips through the real filesystem', () async {
      final store = RealAppSettingsStore(directory: temp);
      const settings = AppSettings(
        recentProjects: ['one.phi', 'two.phi'],
        autosaveInterval: Duration(seconds: 45),
      );
      await store.save(settings);

      // The file is really on disk.
      expect(
        await File(p.join(temp.path, RealAppSettingsStore.fileName)).exists(),
        isTrue,
      );
      expect(await store.load(), settings);
    });

    test('save creates the settings directory if it is missing', () async {
      final nested = Directory(p.join(temp.path, 'phi'));
      final store = RealAppSettingsStore(directory: nested);
      await store.save(const AppSettings(recentProjects: ['a.phi']));
      expect(await nested.exists(), isTrue);
    });

    test('a corrupt settings file falls back to defaults', () async {
      await File(
        p.join(temp.path, RealAppSettingsStore.fileName),
      ).writeAsString('{ not json');
      final store = RealAppSettingsStore(directory: temp);
      expect(await store.load(), const AppSettings());
    });

    test('round-trips audio/midi/pins through the real filesystem', () async {
      final store = RealAppSettingsStore(directory: temp);
      const settings = AppSettings(
        recentProjects: ['one.phi'],
        pinnedProjects: ['pinned.phi'],
        autosaveInterval: Duration(seconds: 45),
        audio: AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Fireface UCX',
          sampleRate: 48000,
          bufferSize: 256,
          layout: SpeakerLayout.surround51,
        ),
        midi: MidiSettings(
          outputPort: 'loopMIDI Port',
          inputPorts: ['Keystation 61'],
        ),
      );
      await store.save(settings);
      expect(await store.load(), settings);
    });

    test(
      'an old settings.json without the new keys loads to defaults',
      () async {
        // A file hand-written in the pre-settings-and-devices schema.
        await File(
          p.join(temp.path, RealAppSettingsStore.fileName),
        ).writeAsString('{"recentProjects":["old.phi"],"autosaveSeconds":60}');
        final store = RealAppSettingsStore(directory: temp);
        final loaded = await store.load();
        expect(loaded.recentProjects, ['old.phi']);
        expect(loaded.pinnedProjects, isEmpty);
        expect(loaded.audio, const AudioSettings());
        expect(loaded.midi, const MidiSettings());
        expect(loaded.version, AppSettings.schemaVersion);
      },
    );
  });
}
