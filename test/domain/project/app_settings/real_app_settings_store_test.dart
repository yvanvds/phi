import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/real_app_settings_store.dart';

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
  });
}
