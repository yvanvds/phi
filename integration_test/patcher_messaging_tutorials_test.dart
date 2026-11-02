import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_engine_log_source.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/log_panel.dart';
import 'package:phi/shell/diagnostics/log_panel_toggle.dart';
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
import '../test/surfaces/patcher/test_support/until_window_active.dart';

/// End-to-end proof of the **I/O, messaging and value tutorials** (issue
/// #504) through the real [PhiApp]: real rail navigation, fonts and layout,
/// the real asset bundle, the real patcher engine ([RealPatcherGateway] on an
/// offline libyse session) and the real engine log feeding the log panel.
/// Only the audio device and MIDI are fakes.
///
/// The forward, value, print and s-r tutorials are opened from the palette's
/// Tutorials tab by searching for one of their types. The test checks that the
/// notes render and nothing overlaps, then plays the patches with real taps
/// and real typing into number boxes, and reads the results back from the
/// canvas, the way the notes tell the user to. print's lines are read from the
/// log panel, opened with Ctrl+J right after typing into a number box (#537).
/// The s-r tutorial is copied to the project, and a value published at
/// `patcher.tutorials.s_r.pitch` (what the Code surface's
/// `patch.tutorials.s_r.send('pitch', 67)` publishes) reaches its `r pitch`. None of them makes a sound, so master stays silent throughout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every I/O, messaging and value tutorial opens from '
      'the Tutorials tab and does what its notes say', (tester) async {
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
      // print writes to the engine log, which the log panel shows.
      engineLogSource: const RealEngineLogSource(),
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
          newLocationPath: '/projects/messaging-tutorials.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    // The first visit leaves the new project's empty patch empty and stopped
    // (#523): nothing is mounted, and master stays silent.
    expect(engine.patcher.graph.nodes, isEmpty);
    expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.tutorials)),
    );
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    final patchCount = project.registry
        .childrenOfKind(RegistryKinds.patch)
        .length;

    // Renders [blocks] blocks of the offline session and returns the loudest
    // master peak among them. A send reaches its receive, and print writes
    // its lines, as blocks are rendered.
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

    // Opens [type]'s tutorial from the browser and checks the banner, the
    // slug and the notes.
    Future<void> open(
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
      expect(
        find.byKey(PatchTutorialBar.bannerKey),
        findsOneWidget,
        reason: '$slug tutorial banner',
      );
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
      // Every tutorial is mounted while open (#528). libyse sets the sound
      // up on a worker thread, in wall-clock time: render with real pauses
      // until it is in the mix (#525).
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
      loudness(20);
    }

    Future<void> tap(Finder f) async {
      expect(f, findsOneWidget, reason: 'tap target: $f');
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    // Closes the tutorial. Back on the project patch, still stopped (#523).
    Future<void> close() async {
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

    Finder buttonAt(double x, double y) => find.descendant(
      of: nodeAt('.b', x, y),
      matching: find.byType(PatchBangSquare),
    );

    Finder numberField(String type, double x, double y) => find.descendant(
      of: nodeAt(type, x, y),
      matching: find.descendant(
        of: find.byType(NumberNodeBody),
        matching: find.byType(TextField),
      ),
    );

    // What the number box at ([x], [y]) shows on the canvas, once a few
    // blocks have run and the surface's live-value poll has come due.
    Future<double> shown(String type, double x, double y) async {
      loudness(5);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final field = numberField(type, x, y);
      expect(field, findsOneWidget, reason: '$type at ($x, $y)');
      return double.parse(tester.widget<TextField>(field).controller!.text);
    }

    // Types [text] into the number box at ([x], [y]) and commits it, which
    // sends it on (#544: through the shared helper, which survives the
    // window going inactive mid-typing).
    Future<void> typeInto(String type, double x, double y, String text) async {
      final field = numberField(type, x, y);
      await typeIntoField(tester, field, text, what: '$type at ($x, $y)');
    }

    // ── forward: a name chosen as it runs ───────────────────────────────────
    await open(
      '.forward',
      slug: 'forward',
      notes: 4,
      heading: 'forward sends what reaches its left inlet',
    );
    await typeInto('.i', 60, 160, '5');
    expect(await shown('.i', 60, 400), 0, reason: 'no name yet');
    expect(await shown('.i', 200, 400), 0);
    await tap(message('left'));
    await typeInto('.i', 60, 160, '7');
    expect(await shown('.i', 60, 400), 7);
    expect(await shown('.i', 200, 400), 0);
    await tap(message('right'));
    await typeInto('.i', 60, 160, '8');
    expect(await shown('.i', 200, 400), 8);
    expect(await shown('.i', 60, 400), 7, reason: 'left keeps 7');
    await tap(message('nowhere'));
    await typeInto('.i', 60, 160, '9');
    expect(await shown('.i', 60, 400), 7, reason: 'lost');
    expect(await shown('.i', 200, 400), 8, reason: 'lost');
    await close();

    // ── value: one value shared by name ─────────────────────────────────────
    await open(
      '.value',
      slug: 'value',
      notes: 4,
      heading: 'Every value with the same name holds the same value',
    );
    await tap(buttonAt(360, 160));
    expect(await shown('.f', 360, 280), 0.5, reason: 'the starting value');
    await typeInto('.f', 60, 160, '0.8');
    expect(await shown('.f', 360, 280), 0.5, reason: 'only stored');
    await tap(buttonAt(360, 160));
    expect(await shown('.f', 360, 280), closeTo(0.8, 1e-6));
    await tap(message('0.25'));
    await tap(buttonAt(360, 160));
    expect(await shown('.f', 360, 280), 0.25);
    await close();

    // ── print: lines in the log panel ───────────────────────────────────────
    await open(
      '.print',
      slug: 'print',
      notes: 4,
      heading: 'print writes every message that reaches it',
    );
    // Ctrl+J, the way note 1 says. The tutorial was opened from the search
    // field and a number box has just let go of the keyboard, so this proves
    // the shell's shortcuts survive a field releasing focus (#537).
    //
    // Keys reach the shell's bindings only while its window is active: an
    // `inactive` window parks the focus on the root scope, above them, until
    // the window is back, the way a real keyboard cannot reach an unfocused
    // window (#544). So give an inactive window its grace first, and press
    // again (up to three tries) should it lose focus in that last instant.
    Future<void> pressCtrlJ() async {
      for (var attempt = 0; attempt < 3; attempt++) {
        await untilWindowActive(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        if (find.byType(LogPanel).evaluate().isNotEmpty) return;
      }
    }

    Finder logRow(String text) => find.descendant(
      of: find.byType(LogPanel),
      matching: find.textContaining(text),
    );
    // Checks the log panel shows [text] [matcher] times, naming the lines it
    // does show when it does not (#544).
    void expectLog(String text, Matcher matcher, [String why = '']) {
      final lines = [
        for (final e
            in find
                .descendant(
                  of: find.byType(LogPanel),
                  matching: find.byType(Text),
                )
                .evaluate())
          (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText(),
      ];
      expect(
        logRow(text),
        matcher,
        reason: 'log line "$text" $why; the panel shows: ${lines.join(' | ')}',
      );
    }

    // The engine's lines reach the panel through a port: render, then let
    // them arrive.
    Future<void> settleLog() async {
      loudness(5);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    expect(find.byType(LogPanel), findsNothing);
    await typeInto('.i', 60, 160, '60');
    await pressCtrlJ();
    expect(
      find.byType(LogPanel),
      findsOneWidget,
      reason:
          'Ctrl+J (#537) opened the log '
          '(app lifecycle: ${WidgetsBinding.instance.lifecycleState}, '
          'focus: ${FocusManager.instance.primaryFocus})',
    );
    await settleLog();
    expectLog('pitch: 60', findsOneWidget);
    await tap(message('hello'));
    await tap(buttonAt(310, 160));
    await settleLog();
    expectLog('print: hello', findsOneWidget);
    expectLog('print: bang', findsOneWidget);
    await tap(buttonAt(60, 320));
    await settleLog();
    expectLog('flood: 1', findsOneWidget);
    expectLog('flood: 2', findsOneWidget);
    expectLog('further messages dropped', findsOneWidget);
    expectLog('flood: 3', findsNothing, 'two lines per tick');
    // The status bar's toggle closes it again.
    await tap(find.byKey(LogPanelToggle.toggleKey));
    expect(find.byType(LogPanel), findsNothing);
    await close();

    // ── s and r: wireless sends, then the bus from a project copy ───────────
    await open(
      '.s',
      slug: 's-r',
      notes: 4,
      heading: 's sends whatever reaches it to the r with the same name',
    );
    await typeInto('.i', 60, 160, '64');
    expect(await shown('.i', 330, 220), 64);
    await tap(message('72'));
    expect(await shown('.i', 330, 220), 72);
    await tap(buttonAt(60, 300));
    final first = await shown('.i', 330, 420);
    await tap(buttonAt(60, 300));
    expect(await shown('.i', 330, 420), first + 1, reason: 'counts clicks');
    expectListBoxesUncut(tester, where: 's-r');
    // Note 3: COPY TO PROJECT makes patch.tutorials.s_r, on the engine bus.
    await tap(find.byKey(PatchTutorialBar.copyKey));
    expect(library.tutorial, isNull);
    expect(library.openAddress, EntityAddress.parse('patch.tutorials.s_r'));
    // What patch.tutorials.s_r.send('pitch', 67) publishes from Code.
    Bus.publish('patcher.tutorials.s_r.pitch', const BusFloat(67));
    loudness(5);
    final copy = gateway.enumerate(engine.patcher.instanceId);
    final pitchBox = copy.objects
        .firstWhere(
          (o) => o.type == '.i' && o.position == const Offset(330, 220),
        )
        .handleId;
    expect(gateway.guiValue(engine.patcher.instanceId, pitchBox), '67');
    expect(await shown('.i', 330, 220), 67, reason: 'on the canvas');

    expect(loudness(), 0, reason: 'nothing here makes a sound');
    expect(
      project.registry.childrenOfKind(RegistryKinds.patch).length,
      patchCount + 1,
      reason: 'only the copy was added to the project',
    );

    await tester.pumpWidget(const SizedBox());
    await engine.dispose();
    await yse.dispose();
  });
}
