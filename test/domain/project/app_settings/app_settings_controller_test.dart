import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';

import '../test_doubles/fake_app_settings_store.dart';

void main() {
  group('AppSettingsController', () {
    test('starts at defaults before load', () {
      final controller = AppSettingsController(FakeAppSettingsStore());
      addTearDown(controller.dispose);

      expect(controller.value, const AppSettings());
    });

    test('load reads the persisted value and notifies', () async {
      const persisted = AppSettings(
        recentProjects: ['seed.phi'],
        autosaveInterval: Duration(seconds: 5),
      );
      final controller = AppSettingsController(FakeAppSettingsStore(persisted));
      addTearDown(controller.dispose);
      var notes = 0;
      controller.addListener(() => notes++);

      await controller.load();

      expect(controller.value, persisted);
      expect(notes, 1);
    });

    test('update sets the value, persists it, and notifies', () async {
      final store = FakeAppSettingsStore();
      final controller = AppSettingsController(store);
      addTearDown(controller.dispose);
      var notes = 0;
      controller.addListener(() => notes++);

      final next = const AppSettings().withRecentProject('a.phi');
      await controller.update(next);

      expect(controller.value, next);
      expect(store.current, next); // the single writer reached the file
      expect(store.saveCount, 1);
      expect(notes, 1);
    });

    test('update to an equal value neither writes nor notifies', () async {
      final store = FakeAppSettingsStore();
      final controller = AppSettingsController(store);
      addTearDown(controller.dispose);
      await controller.update(const AppSettings().withRecentProject('a.phi'));
      final savesAfterFirst = store.saveCount;
      var notes = 0;
      controller.addListener(() => notes++);

      // Same value again — a redundant update is a no-op.
      await controller.update(controller.value);

      expect(store.saveCount, savesAfterFirst);
      expect(notes, 0);
    });

    test(
      'value and notification apply synchronously, before the save resolves',
      () {
        final store = FakeAppSettingsStore();
        final controller = AppSettingsController(store);
        addTearDown(controller.dispose);
        var notes = 0;
        controller.addListener(() => notes++);

        // Fire-and-forget (as the recents path does): the value is live and the
        // listeners have fired before the returned future is awaited.
        final next = const AppSettings().withRecentProject('a.phi');
        controller.update(next);

        expect(controller.value, next);
        expect(notes, 1);
      },
    );

    test(
      'recents and an audio edit funnel through one writer — the last wins',
      () async {
        final store = FakeAppSettingsStore();
        final controller = AppSettingsController(store);
        addTearDown(controller.dispose);

        // A recents write (as the lifecycle controller does) …
        await controller.update(controller.value.withRecentProject('set.phi'));
        // … then an audio-section edit (as the settings dialog will) — both go
        // through the same [update], so the file always reflects the latest
        // whole value; there is no second writer to race with.
        await controller.update(
          AppSettings(
            recentProjects: controller.value.recentProjects,
            audio: const AudioSettings(outputDevice: 'Fireface UCX'),
          ),
        );

        expect(store.current.recentProjects, ['set.phi']);
        expect(store.current.audio.outputDevice, 'Fireface UCX');
        expect(store.saveCount, 2);
      },
    );
  });
}
