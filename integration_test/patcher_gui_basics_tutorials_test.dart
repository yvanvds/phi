import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette_tab.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_browser.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **GUI basics tutorials** (issue #490) through the
/// real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// Each of `.b`, `.t`, `.slider`, `.i`, `.f`, `.m` and `.text` is opened
/// from the palette's Tutorials tab. The test checks that its notes render,
/// then plays the control the tutorial is about with real taps and reads the
/// result back from the engine, the way the notes tell the user to.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every GUI basics tutorial opens from the Tutorials '
      'tab and its controls do what its notes say', (tester) async {
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
      telemetryInterval: const Duration(milliseconds: 20),
    );
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
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/gui-basics.phi',
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
    final patchCount = project.registry
        .childrenOfKind(RegistryKinds.patch)
        .length;

    // Opens [type]'s tutorial from the browser and checks the banner, the
    // slug and the notes. Returns a lookup of objects by type and position.
    Future<int Function(String, double, double)> open(
      String type, {
      required String slug,
      required int notes,
      required String heading,
    }) async {
      final entry = find.byKey(PatchTutorialBrowser.entryKey(type));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final tutorial = library.tutorial;
      expect(tutorial, isNotNull, reason: type);
      expect(tutorial!.slug, slug);
      expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);
      expect(find.byType(PatchNoteBox), findsNWidgets(notes), reason: slug);
      expect(
        find.textContaining(heading, findRichText: true),
        findsOneWidget,
        reason: '$slug title note',
      );
      // Laid out legibly in the real font: no note or object overlaps
      // another one on the canvas.
      final boxes = [
        for (final e in find.byType(PatcherNodeView).evaluate())
          (
            tester.widget<PatcherNodeView>(find.byWidget(e.widget)).node,
            tester.getRect(find.byWidget(e.widget)),
          ),
      ];
      final overlaps = [
        for (var i = 0; i < boxes.length; i++)
          for (var j = i + 1; j < boxes.length; j++)
            if (boxes[i].$2.overlaps(boxes[j].$2))
              '${boxes[i].$1.type} ${boxes[i].$2} / '
                  '${boxes[j].$1.type} ${boxes[j].$2}',
      ];
      expect(overlaps, isEmpty, reason: '$slug: overlapping nodes');
      final graph = gateway.enumerate(tutorial.instanceId);
      return (String t, double x, double y) => graph.objects
          .firstWhere((o) => o.type == t && o.position == Offset(x, y))
          .handleId;
    }

    String value(int id) => gateway.guiValue(library.tutorial!.instanceId, id);

    Future<void> tap(Finder f) async {
      expect(f, findsOneWidget);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> close() => tap(find.byKey(PatchTutorialBar.closeKey));

    // ── .b: a click and a number both press the button ──────────────────────
    var at = await open(
      '.b',
      slug: 'b',
      notes: 5,
      heading: 'turns anything that reaches it into a bang',
    );
    await tap(find.byType(PatchBangSquare));
    expect(value(at('.i', 60, 400)), '1', reason: 'the click counted');
    await tap(message('42'));
    expect(value(at('.i', 60, 400)), '2', reason: 'a number presses it');
    await close();

    // ── .t: click on, bang flips, the metro runs while on ───────────────────
    at = await open('.t', slug: 't', notes: 5, heading: 'A toggle is a switch');
    await tap(find.byType(PatchToggleSquare));
    expect(value(at('.t', 60, 210)), 'on');
    expect(value(at('.i', 60, 290)), '1');
    expect(value(at('.i', 180, 410)), '1', reason: 'the metro started');
    await tap(find.byType(PatchBangSquare));
    expect(value(at('.i', 60, 290)), '0', reason: 'a bang flips it off');
    await close();

    // ── .slider: loaded at 0.5 → 1100 Hz, clamped by 2, plays on master ─────
    at = await open(
      '.slider',
      slug: 'slider',
      notes: 5,
      heading: 'A slider holds a position from 0',
    );
    expect(library.tutorial!.mounted, isTrue, reason: 'audible on master');
    expect(double.parse(value(at('.f', 60, 360))), 0.5);
    expect(double.parse(value(at('.f', 170, 420))), 1100.0);
    await tap(message('2'));
    expect(double.parse(value(at('.slider', 60, 190))), 1.0);
    expect(double.parse(value(at('.f', 170, 420))), 2000.0);
    await close();

    // ── .i (and .f, same tutorial): cold inlet, resend, truncation ──────────
    at = await open(
      '.i',
      slug: 'number-boxes',
      notes: 5,
      heading: 'A number box shows a number',
    );
    await tap(message('7'));
    await tap(message('99'));
    expect(value(at('.i', 60, 200)), '99');
    expect(value(at('.i', 60, 270)), '7', reason: 'the right inlet is cold');
    await tap(find.byType(PatchBangSquare));
    expect(value(at('.i', 60, 270)), '99', reason: 'a bang resends');
    await tap(message('-2.9'));
    expect(value(at('.i', 60, 420)), '-2');
    expect(double.parse(value(at('.f', 170, 420))), -2.9);
    await close();
    await open(
      '.f',
      slug: 'number-boxes',
      notes: 5,
      heading: 'A number box shows a number',
    );
    await close();

    // ── .m: a command, and a message replaced from the inlet ────────────────
    at = await open(
      '.m',
      slug: 'm',
      notes: 5,
      heading: 'A message box holds a line of text',
    );
    await tap(message('bang'));
    expect(value(at('.i', 60, 440)), '1');
    await tap(message('1 2 3'));
    expect(value(at('.i', 60, 650)), '0', reason: 'replacing sends nothing');
    await tap(message('0'));
    expect(value(at('.i', 60, 650)), '1', reason: 'it now sends 1 2 3');
    await close();

    // ── .text: notes all the way down ───────────────────────────────────────
    await open(
      '.text',
      slug: 'text',
      notes: 6,
      heading: 'A note is a comment on the canvas',
    );
    await close();

    expect(library.tutorial, isNull);
    expect(
      project.registry.childrenOfKind(RegistryKinds.patch).length,
      patchCount,
      reason: 'opening tutorials never touches the project',
    );

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
    project.dispose();
    appSettings.dispose();
    session.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
