import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/session/session_state.dart';

import '../test_doubles/fake_app_settings_store.dart';
import '../test_doubles/fake_journal_store.dart';
import '../test_doubles/fake_project_store.dart';

void main() {
  group('ProjectController registry seeding', () {
    late SessionState session;

    setUp(() => session = SessionState());
    tearDown(() => session.dispose());

    ProjectController controllerWith(void Function(ProjectRegistry)? seed) {
      final settings = AppSettingsController(FakeAppSettingsStore());
      addTearDown(settings.dispose);
      return ProjectController(
        session: session,
        settings: settings,
        storeFactory: (_) => FakeProjectStore(),
        journalStoreFactory: (_) => FakeJournalStore(),
        seedRegistry: seed,
        autosaveIntervalOverride: const Duration(hours: 1),
      );
    }

    test('newProject seeds the default entities when a seeder is given', () {
      final controller = controllerWith(seedDefaultProject);
      addTearDown(controller.dispose);

      controller.newProject();

      expect(
        controller.registry.contains(EntityAddress.parse('clip.phrase_a')),
        isTrue,
      );
      expect(
        controller.registry.contains(EntityAddress.parse('domain.drum')),
        isTrue,
      );
      // Seeding is initial state, not an edit — the project stays clean.
      expect(controller.isDirty.value, isFalse);
    });

    test('newProject leaves an empty registry without a seeder', () {
      final controller = controllerWith(null);
      addTearDown(controller.dispose);

      controller.newProject();

      expect(controller.registry.kinds, isEmpty);
    });
  });
}
