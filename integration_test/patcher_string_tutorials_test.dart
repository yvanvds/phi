import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_text_edit_box.dart';
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
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette_tab.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
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
import '../test/surfaces/patcher/test_support/type_into_field.dart';

/// End-to-end proof of the **string tutorials** (issue #503) through the real
/// [PhiApp]: real rail navigation, fonts and layout, the real asset bundle
/// and the real patcher engine ([RealPatcherGateway] on an offline libyse
/// session). Only the audio device and MIDI are fakes.
///
/// The sprintf, regexp, tosymbol-fromsymbol, atoi-itoa, combine, spell and
/// tolower-toupper tutorials are opened from the palette's Tutorials tab by
/// searching for one of their types. The test checks that the notes render and
/// nothing overlaps, then plays the patches with real taps on message boxes and
/// buttons and real typing into number boxes and text fields, and reads the
/// results back from the canvas and the engine, the way the notes tell the
/// user to. Every list box result must fit its box, not be cut off with an
/// ellipsis. None of them makes a sound, so master stays silent throughout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every string tutorial opens from the Tutorials '
      'tab and does what its notes say', (tester) async {
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
          newLocationPath: '/projects/string-tutorials.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    // The first visit leaves the new project's empty patch empty and stopped
    // (#523): nothing is mounted, and master stays silent, so the meter below
    // hears only the tutorials.
    expect(engine.patcher.graph.nodes, isEmpty);
    expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    var idle = 0.0;
    for (var i = 0; i < 400; i++) {
      System.instance
        ..renderOffline(1)
        ..update();
      final p = Channel.master.peakLinearPost();
      if (p > idle) idle = p;
    }
    expect(idle, 0, reason: 'nothing plays before a tutorial opens');
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
      // Search for the type, the way a user finds it (#524, #527).
      await openTutorialBySearch(tester, type);
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
      // Every tutorial is mounted while open, a silent one too (#528).
      // libyse sets the new sound up on a worker thread, in wall-clock
      // time, while an offline render runs far ahead of real time. Render
      // with real pauses until the sound is in the mix, so that nothing
      // below measures blocks rendered before it joined (#525).
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(tutorial.instanceId)) break;
        System.instance
          ..renderOffline(1)
          ..update();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        gateway.isSourceReady(tutorial.instanceId),
        isTrue,
        reason: '$slug joined the mix',
      );
      // And let whatever the last tutorial left ringing drain away.
      for (var i = 0; i < 20; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
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

    // Closes the tutorial. Back on the project patch, which is still empty
    // and stopped (#523).
    Future<void> close() async {
      // Every list box result the walk-through left must show in full.
      expectListBoxesUncut(
        tester,
        where: engine.patchLibrary.tutorial?.slug ?? '',
      );
      await tap(find.byKey(PatchTutorialBar.closeKey));
      expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    }

    // The canvas view of the [type] object placed at ([x], [y]).
    Finder nodeAt(String type, double x, double y) => find.byWidgetPredicate(
      (w) =>
          w is PatcherNodeView &&
          w.node.type == type &&
          w.node.position == Offset(x, y),
    );

    // Renders [blocks] blocks of the offline session and returns the loudest
    // master peak among them: what reaches the speakers.
    double loudness([int blocks = 200]) {
      var peak = 0.0;
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
        final p = Channel.master.peakLinearPost();
        if (p > peak) peak = p;
      }
      return peak;
    }

    // The button at ([x], [y]).
    Finder buttonAt(double x, double y) => find.descendant(
      of: nodeAt('.b', x, y),
      matching: find.byType(PatchBangSquare),
    );

    // What the number box at ([x], [y]) shows on the canvas, once the
    // surface's live-value poll has come due.
    Future<double> shown(String type, double x, double y) async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: nodeAt(type, x, y),
        matching: find.descendant(
          of: find.byType(NumberNodeBody),
          matching: find.byType(TextField),
        ),
      );
      expect(field, findsOneWidget, reason: '$type at ($x, $y)');
      return double.parse(tester.widget<TextField>(field).controller!.text);
    }

    // Types [text] into the number box at ([x], [y]) and commits it, which
    // sends it on (#544: through the shared helper, which survives the
    // window going inactive mid-typing).
    Future<void> typeInto(String type, double x, double y, String text) async {
      final field = find.descendant(
        of: nodeAt(type, x, y),
        matching: find.descendant(
          of: find.byType(NumberNodeBody),
          matching: find.byType(TextField),
        ),
      );
      await typeIntoField(tester, field, text, what: '$type at ($x, $y)');
    }

    // Whether a list box on the canvas shows [text] in full, once the
    // live-value poll has come due. A list box cuts a long list off with an
    // ellipsis, so a tutorial's results must fit the box to be read.
    Future<bool> listShows(String text) async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final shown = find.descendant(
        of: find.byType(PatchListBox),
        matching: find.text(text),
      );
      if (shown.evaluate().isEmpty) return false;
      for (final e in shown.evaluate()) {
        expectListTextFits(e);
      }
      return true;
    }

    // Types [text] into the text field at ([x], [y]) and presses Enter, which
    // stores it and sends it on. With no [text], only clicks the field and
    // presses Enter: the text it holds is sent as it is.
    Future<void> enterInto(double x, double y, [String? text]) async {
      final field = find.descendant(
        of: nodeAt('.textedit', x, y),
        matching: find.descendant(
          of: find.byType(PatchTextEditBox),
          matching: find.byType(EditableText),
        ),
      );
      expect(field, findsOneWidget, reason: 'textedit at ($x, $y)');
      await tester.tap(field);
      await tester.pumpAndSettle();
      tester.binding.focusedEditable = null;
      if (text != null) {
        await tester.enterText(field, text);
        await tester.pump();
      } else {
        await tester.showKeyboard(field);
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    // ── sprintf: a unit, two inlets, width and precision ────────────────────
    var at = await open(
      '.sprintf',
      slug: 'sprintf',
      notes: 5,
      heading: 'sprintf fills the placeholders in a format',
    );
    await typeInto('.i', 60, 200, '440');
    expect(await listShows('440 Hz'), isTrue);
    await tap(message('90'));
    expect(value(at('.l', 300, 320)), '', reason: 'the right inlet stores');
    await tap(message('60'));
    expect(await listShows('note 60 90'), isTrue);
    await typeInto('.i', 60, 420, '7');
    expect(await listShows('007.wav'), isTrue);
    await typeInto('.f', 300, 420, '0.5');
    expect(await listShows('gain 0.50'), isTrue);
    await close();

    // ── regexp: matches, groups, substitution, no match ─────────────────────
    at = await open(
      '.regexp',
      slug: 'regexp',
      notes: 5,
      heading: 'regexp looks for a regular expression in every message',
    );
    await tap(buttonAt(60, 220));
    expect(await listShows('c#4 e#5 g'), isTrue, reason: 'substitution');
    expect(await listShows('e 5'), isTrue, reason: 'the groups');
    expect(await listShows('e5'), isTrue, reason: 'the last match');
    expect(await shown('.i', 500, 540), 2, reason: 'two matches');
    await tap(message('hat'));
    expect(await listShows('hat'), isTrue, reason: 'no match: right outlet');
    expect(await shown('.i', 500, 540), 2);
    await enterInto(60, 270, 'a1 b2 x');
    expect(await listShows('a#1 b#2 x'), isTrue, reason: 'typed text');
    expect(await shown('.i', 500, 540), 4);
    await close();

    // ── tosymbol and fromsymbol: join, split, parse typed text ──────────────
    at = await open(
      '.fromsymbol',
      slug: 'tosymbol-fromsymbol',
      notes: 5,
      heading: 'tosymbol joins the items of a message into one symbol',
    );
    await tap(buttonAt(60, 220));
    expect(await listShows('osc/3/amp'), isTrue);
    expect(await listShows('osc 3 amp'), isTrue, reason: 'split back');
    await tap(message('-'));
    await tap(buttonAt(60, 220));
    expect(value(at('.l', 60, 390)), 'osc-3-amp');
    expect(value(at('.l', 220, 450)), 'osc-3-amp', reason: 'left whole');
    await enterInto(60, 540, '60,64,67');
    expect(await listShows('60 64 67'), isTrue, reason: 'parsed');
    expect(await shown('.i', 220, 720), 67);
    await enterInto(60, 540, '72');
    expect(await shown('.i', 220, 720), 72, reason: 'one number, an int');
    expect(value(at('.l', 60, 660)), '60 64 67');
    await close();

    // ── atoi and itoa: codes and back, append, bang ─────────────────────────
    at = await open(
      '.atoi',
      slug: 'atoi-itoa',
      notes: 4,
      heading: 'atoi turns the text of a message into its character codes',
    );
    await enterInto(60, 200);
    expect(await listShows('104 105'), isTrue, reason: 'hi as codes');
    expect(await listShows('hi'), isTrue, reason: 'and back');
    await enterInto(60, 200, 'a b');
    expect(await listShows('97 32 98'), isTrue, reason: 'a space is 32');
    await enterInto(60, 200, 'hé');
    expect(await listShows('104 233'), isTrue, reason: 'UTF-8');
    await typeInto('.i', 340, 260, '33');
    expect(value(at('.l', 220, 440)), 'hé', reason: 'added, not sent');
    await tap(buttonAt(460, 260));
    expect(await listShows('hé!'), isTrue);
    await close();

    // ── combine: a file name from items ─────────────────────────────────────
    at = await open(
      '.combine',
      slug: 'combine',
      notes: 4,
      heading: 'combine writes its items one after another',
    );
    await tap(buttonAt(170, 200));
    expect(await listShows('kick-1.wav'), isTrue);
    await typeInto('.i', 240, 200, '2');
    expect(value(at('.l', 60, 330)), 'kick-1.wav', reason: 'stored only');
    await tap(message('hat'));
    expect(await listShows('hat-2.wav'), isTrue);
    await typeInto('.i', 200, 420, '4');
    expect(await listShows('bus/4'), isTrue, reason: 'triggers -1');
    await close();

    // ── spell: codes, iter, padding ─────────────────────────────────────────
    at = await open(
      '.spell',
      slug: 'spell',
      notes: 4,
      heading: "spell sends the character codes of a message's text",
    );
    await enterInto(60, 200);
    expect(await listShows('104 105'), isTrue);
    expect(await shown('.i', 220, 380), 105, reason: 'iter: the last code');
    await enterInto(60, 200, 'a b');
    expect(await listShows('97 32 98'), isTrue);
    await typeInto('.i', 60, 460, '7');
    expect(await listShows('55 48 48'), isTrue, reason: 'padded with 0s');
    await close();

    // ── tolower and toupper: case, route ignoring it ────────────────────────
    at = await open(
      '.toupper',
      slug: 'tolower-toupper',
      notes: 3,
      heading: 'tolower makes the letters A to Z lower case',
    );
    await enterInto(60, 180);
    expect(await listShows('HELLO'), isTrue);
    expect(await listShows('hello'), isTrue);
    await enterInto(60, 180, 'Grüße 42');
    expect(await listShows('GRüßE 42'), isTrue, reason: 'ü, ß, 42 kept');
    expect(await listShows('grüße 42'), isTrue);
    await tap(message('PLAY'));
    await tap(message('Stop'));
    expect(await shown('.i', 60, 650), 1, reason: 'PLAY counted as play');
    expect(await shown('.i', 170, 650), 1, reason: 'Stop counted as stop');
    await enterInto(280, 400, 'pLaY');
    expect(await shown('.i', 60, 650), 2);
    await enterInto(280, 400, 'Pause');
    expect(await listShows('pause'), isTrue, reason: 'the rest, lowered');
    expect(await shown('.i', 60, 650), 2);
    await close();

    expect(loudness(), 0, reason: 'nothing here makes a sound');
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
