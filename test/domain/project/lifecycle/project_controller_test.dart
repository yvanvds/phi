import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/recovery/recovery_offer.dart';
import 'package:phi/domain/session/session_state.dart';

import '../test_doubles/fake_app_settings_store.dart';
import '../test_doubles/fake_journal_store.dart';
import '../test_doubles/fake_project_store.dart';

/// A controller wired to in-memory fakes plus the fakes themselves, so a test
/// can drive the lifecycle and inspect what was written.
class _Harness {
  _Harness({Duration? autosaveIntervalOverride})
    : session = SessionState(),
      store = FakeProjectStore(),
      journal = FakeJournalStore(),
      settingsStore = FakeAppSettingsStore() {
    settings = AppSettingsController(settingsStore);
    controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      autosaveIntervalOverride: autosaveIntervalOverride,
    );
  }

  final SessionState session;
  final FakeProjectStore store;
  final FakeJournalStore journal;
  final FakeAppSettingsStore settingsStore;
  late final AppSettingsController settings;
  late final ProjectController controller;

  void dispose() {
    controller.dispose();
    settings.dispose();
    session.dispose();
  }
}

void main() {
  const dir = '/projects/my_set.phi';

  _Harness harness({Duration? autosaveIntervalOverride}) {
    final h = _Harness(autosaveIntervalOverride: autosaveIntervalOverride);
    addTearDown(h.dispose);
    return h;
  }

  group('ProjectController — new / dirty', () {
    test('newProject resets name + session and is not dirty', () {
      final h = harness();
      h.session.renameScene('verse');
      expect(h.controller.isDirty.value, isTrue);

      h.controller.newProject(projectName: 'fresh');
      expect(h.controller.name.value, 'fresh');
      expect(h.controller.isDirty.value, isFalse);
      // The manifest defaults are applied — a new project is a clean slate.
      expect(h.session.sceneName.value, 'untitled');
      expect(h.session.tempo.value, 120);
      expect(h.controller.isSaved, isFalse);
    });

    test('a manifest-level session change marks the project dirty', () {
      final h = harness();
      expect(h.controller.isDirty.value, isFalse);
      h.session.setTempo(140);
      expect(h.controller.isDirty.value, isTrue);
    });
  });

  group('ProjectController — save / saveAs', () {
    test('save() before a location is chosen throws', () {
      final h = harness();
      expect(h.controller.save(), throwsStateError);
    });

    test('saveAs writes the folder, binds it, and records a recent', () async {
      final h = harness();
      await h.controller.saveAs(dir);

      expect(h.store.saveCount, 1);
      expect(h.store.files.containsKey('project.json'), isTrue);
      expect(h.controller.isSaved, isTrue);
      expect(h.controller.location.value, dir);
      // The project is named after the `<name>.phi` folder it was saved into.
      expect(h.controller.name.value, 'my_set');
      expect(h.controller.isDirty.value, isFalse);
      expect(h.controller.recentProjects.value, [dir]);
      expect(h.settingsStore.current.recentProjects, contains(dir));
    });

    test('save persists the current session state into the manifest', () async {
      final h = harness();
      await h.controller.saveAs(dir);
      h.session
        ..renameScene('bridge')
        ..setTempo(90);
      expect(h.controller.isDirty.value, isTrue);

      await h.controller.save();
      expect(h.controller.isDirty.value, isFalse);

      final reloaded = await h.store.load();
      expect(reloaded.manifest.sceneName, 'bridge');
      expect(reloaded.manifest.tempo, 90);
    });

    test('save persists the master volume/mute into the manifest', () async {
      final h = harness();
      await h.controller.saveAs(dir);
      h.session
        ..setMasterVolume(0.42)
        ..setMasterMuted(true);
      expect(h.controller.isDirty.value, isTrue); // a master change dirties

      await h.controller.save();

      final reloaded = await h.store.load();
      expect(reloaded.manifest.masterVolume, closeTo(0.42, 1e-9));
      expect(reloaded.manifest.masterMuted, isTrue);
    });
  });

  group('ProjectController — open', () {
    test(
      'open reloads the manifest into the session and clears dirty',
      () async {
        final h = harness();
        await h.controller.saveAs(dir); // manifest: tempo 120, scene untitled
        h.session.setTempo(90); // dirties + diverges from disk
        expect(h.controller.isDirty.value, isTrue);

        await h.controller.open(dir);
        expect(h.session.tempo.value, 120); // reverted to the saved manifest
        expect(h.controller.isDirty.value, isFalse);
        expect(h.controller.location.value, dir);
      },
    );

    test('open restores the master volume/mute without dirtying', () async {
      final h = harness();
      h.session
        ..setMasterVolume(0.3)
        ..setMasterMuted(true);
      await h.controller.saveAs(dir); // manifest carries master 0.3 / muted
      // Diverge the live session from disk.
      h.session
        ..setMasterVolume(0.9)
        ..setMasterMuted(false);

      await h.controller.open(dir);

      expect(h.session.masterVolume.value, closeTo(0.3, 1e-9));
      expect(h.session.masterMuted.value, isTrue);
      expect(h.controller.isDirty.value, isFalse); // a clean load stays clean
    });

    test(
      'a dirty journal triggers recovery and is replayed + resolved',
      () async {
        final h = harness();
        await h.controller.saveAs(dir); // clean save; journal truncated
        // Seed the journal with one applied-but-unsaved create command.
        await h.journal.append(
          jsonEncode(const {'type': 'create_entity', 'address': 'clip.demo'}),
        );

        RecoveryOffer? seen;
        await h.controller.open(
          dir,
          prompt: (offer) async {
            seen = offer;
            return RecoveryChoice.replayAll;
          },
        );

        expect(seen, isNotNull);
        expect(seen!.entryCount, 1);
        // The replayed command rebuilt the entity …
        expect(
          h.controller.registry.entityAt(EntityAddress.parse('clip.demo')),
          isNotNull,
        );
        // … and the journal was resolved (truncated) after the clean re-save.
        expect(h.journal.lines, isEmpty);
      },
    );

    test(
      'dismissing the recovery prompt leaves the project untouched',
      () async {
        final h = harness();
        await h.controller.saveAs(dir);
        await h.journal.append(
          jsonEncode(const {'type': 'create_entity', 'address': 'clip.demo'}),
        );

        await h.controller.open(dir, prompt: (offer) async => null);

        expect(
          h.controller.registry.entityAt(EntityAddress.parse('clip.demo')),
          isNull,
        );
        // The journal is left intact for a later attempt.
        expect(h.journal.lines, isNotEmpty);
      },
    );

    test('opening a non-project folder throws', () {
      final h = harness();
      expect(h.controller.open(dir), throwsA(isA<FormatException>()));
    });
  });

  group('ProjectController — autosave / recents / journaling', () {
    test('autosaveNow writes only when bound and dirty', () async {
      final h = harness();
      // Unbound → nothing to autosave.
      expect(await h.controller.autosaveNow(), isFalse);

      await h.controller.saveAs(dir);
      // Bound but clean → still a no-op.
      expect(await h.controller.autosaveNow(), isFalse);

      h.session.renameScene('take 2');
      final before = h.store.saveCount;
      expect(await h.controller.autosaveNow(), isTrue);
      expect(h.store.saveCount, before + 1);
      expect(h.controller.isDirty.value, isFalse);
    });

    test('recordCommand dirties and journals a registry command', () async {
      final h = harness();
      await h.controller.saveAs(dir); // bound; journal empty
      final command = CreateEntityCommand(
        h.controller.registry,
        EntityAddress.parse('clip.demo'),
      );

      h.controller.recordCommand(command);
      expect(h.controller.isDirty.value, isTrue);
      expect(h.journal.appendCount, 1);
    });

    test('forgetRecent drops a path and persists the change', () async {
      final h = harness();
      await h.controller.saveAs(dir);
      expect(h.controller.recentProjects.value, contains(dir));

      h.controller.forgetRecent(dir);
      expect(h.controller.recentProjects.value, isNot(contains(dir)));
      expect(h.settingsStore.current.recentProjects, isNot(contains(dir)));
    });

    test('loadSettings hydrates recents and the autosave cadence', () async {
      final seeded = FakeAppSettingsStore(
        const AppSettings(
          recentProjects: ['seed.phi'],
          autosaveInterval: Duration(seconds: 5),
        ),
      );
      final session = SessionState();
      addTearDown(session.dispose);
      final settings = AppSettingsController(seeded);
      addTearDown(settings.dispose);
      final controller = ProjectController(
        session: session,
        settings: settings,
        storeFactory: (_) => FakeProjectStore(),
        journalStoreFactory: (_) => FakeJournalStore(),
      );
      addTearDown(controller.dispose);

      await controller.loadSettings();
      expect(controller.recentProjects.value, ['seed.phi']);
      expect(controller.autosaveInterval, const Duration(seconds: 5));
    });
  });
}
