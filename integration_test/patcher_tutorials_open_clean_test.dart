import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/domain/log/log_level.dart' as phi;
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_engine_log_source.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/log_panel_toggle.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette_tab.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/patcher/test_support/expect_list_boxes_uncut.dart';
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';

/// **Every bundled tutorial opens without an engine error** (issue #539),
/// through the real [PhiApp]: real rail navigation, the Tutorials tab's
/// search, the real asset bundle, the real patcher engine on an offline libyse
/// session, and the real engine log feeding the log panel and its badge. Only
/// the audio device and MIDI gateway are fakes.
///
/// A tutorial opens as a patch with one main output, so its `~dac` has one
/// inlet. Tutorials used to wire a second cord into a right inlet that did
/// not exist; the engine refused it with `Patcher: Invalid Connection`, and
/// every audio tutorial raised the error badge on the log toggle. This walks
/// every tutorial the index lists, then checks the log holds no error and the
/// badge is not up.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: opening every bundled tutorial logs no engine error '
      'and raises no error badge', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final yse = FakeYseGateway();
    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      yse,
      patcherGateway: gateway,
      midiGateway: FakeMidiGateway(),
      engineLogSource: const RealEngineLogSource(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final notices = NoticeCenter.build();
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final project = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: project,
        noticeCenter: notices,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/every-tutorial.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.tutorials)),
    );
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    final catalog = library.tutorials;
    expect(catalog.isEmpty, isFalse, reason: 'the bundled index loaded');

    // Renders one block of the offline session, then pauses for real: the
    // engine's log lines reach the app through a port, and a closed patch is
    // freed by libyse in wall-clock time.
    Future<void> settle([int blocks = 1]) async {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
      }
      await tester.pump();
    }

    List<String> errors() => [
      for (final e in notices.log.entries)
        if (e.level == phi.LogLevel.error) e.text,
    ];

    // Each tutorial, opened by the first type it covers through the library
    // call the browser's tap and the reference panel's OPEN TUTORIAL make,
    // then rendered on the canvas. (The search field is the user's way in, and
    // the last tutorial below goes through it, but every search waits on the
    // window's focus, which costs too much to repeat a hundred times.)
    final slugs = catalog.slugs.toList()..sort();
    for (final slug in slugs) {
      final type = catalog.typesFor(slug).first;
      final opened = await tester.runAsync(() => library.openTutorial(type));
      expect(opened, isTrue, reason: type);
      await tester.pumpAndSettle();
      expect(library.tutorial?.slug, slug, reason: type);
      expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);
      await settle(5);
      expect(errors(), isEmpty, reason: 'opening the $slug tutorial');
      expectListBoxesUncut(tester, where: slug);
      await tester.tap(find.byKey(PatchTutorialBar.closeKey));
      await tester.pumpAndSettle();
      // A closed tutorial gives its MIDI input subscriptions back only when
      // libyse frees it, a moment later (yse-soundengine#1246).
      await settle(20);
    }

    // The port delivers in order: once a line printed after every open is
    // in the log, every line those opens logged is there too.
    await openTutorialBySearch(tester, '.print');
    expect(library.tutorial?.slug, 'print');
    await tester.tap(
      find.descendant(
        of: find.byType(PatchMessageBox),
        matching: find.text('hello'),
      ),
    );
    await tester.pumpAndSettle();
    bool printed() =>
        notices.log.entries.any((e) => e.text.contains('print: hello'));
    final clock = Stopwatch()..start();
    while (!printed() && clock.elapsed < const Duration(seconds: 10)) {
      await settle();
    }
    expect(printed(), isTrue, reason: 'the engine log reaches the app');

    expect(errors(), isEmpty);
    expect(
      find.byKey(LogPanelToggle.badgeKey),
      findsNothing,
      reason: 'no error badge on the log toggle',
    );
    await tester.tap(find.byKey(PatchTutorialBar.closeKey));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
    notices.dispose();
  });
}
