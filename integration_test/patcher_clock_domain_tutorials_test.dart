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
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';

/// End-to-end proof of the **transport, tempo and domain clock tutorials**
/// (issue #498) through the real [PhiApp]: real rail navigation, fonts and
/// layout, the real asset bundle and the real patcher engine
/// ([RealPatcherGateway] on an offline libyse session). Only the audio device
/// and MIDI are fakes.
///
/// The transport, tempo, timepoint, setclock, when and translate tutorials are
/// opened from the palette's Tutorials tab by searching for their type. The
/// test checks that the notes render and nothing overlaps, then plays the
/// patches with real taps and typing and reads the results back from the
/// canvas and the engine, the way the notes tell the user to. Domain clocks
/// advance with the audio blocks on libYSE 3.1.0, so the test renders blocks
/// to move them; a tap reaches the engine through its message queue, so the
/// checks keep a margin of a block or more.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every transport, tempo and domain clock tutorial '
      'opens from the Tutorials tab and does what its notes say', (
    tester,
  ) async {
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
          newLocationPath: '/projects/clock-tutorials.phi',
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
      await tap(find.byKey(PatchTutorialBar.closeKey));
      expect(gateway.isSourceReady(engine.patcher.instanceId), isFalse);
    }

    double read(int id) => double.parse(value(id));

    // The canvas view of the [type] object placed at ([x], [y]).
    Finder nodeAt(String type, double x, double y) => find.byWidgetPredicate(
      (w) =>
          w is PatcherNodeView &&
          w.node.type == type &&
          w.node.position == Offset(x, y),
    );

    Finder toggleAt(double x, double y) => find.descendant(
      of: nodeAt('.t', x, y),
      matching: find.byType(PatchToggleSquare),
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

    // Lets [ms] milliseconds of real time pass: metro, timer and clocker keep
    // wall-clock time, not the offline render's.
    Future<void> wait(int ms) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    // [ms] milliseconds of audio: what delay, pipe, line, speedlim, qlim and
    // the thresh pair count. One block is 128 frames at 48 kHz.
    void audio(double ms) => loudness((ms * 48 / 128).ceil());

    int whole(int id) => int.parse(value(id));

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

    // ── transport: start, stop, the tempo, the beat on a bang ───────────────
    var at = await open(
      '.transport',
      slug: 'transport',
      notes: 6,
      heading: 'retempos and reads the domain clock',
    );
    final beat = at('.f', 60, 440);
    final bpm = at('.f', 220, 440);
    Future<void> ask() => tap(buttonAt(260, 320));
    await ask();
    expect(read(bpm), 0, reason: 'stopped when it opens');
    final start = read(beat);
    await tap(message('start'));
    audio(1000);
    await ask();
    expect(read(bpm), 120);
    expect(read(beat), closeTo(start + 2, 0.1), reason: 'two beats a second');
    expect(await shown('.f', 220, 440), 120, reason: 'the tempo on screen');
    await tap(message('60'));
    final slower = read(beat);
    audio(1000);
    await ask();
    expect(read(bpm), 60, reason: 'at once while it runs');
    expect(read(beat) - slower, closeTo(1, 0.1));
    await tap(message('stop'));
    await ask();
    final held = read(beat);
    audio(500);
    await ask();
    expect(read(beat), held, reason: 'stop pauses it');
    expect(read(bpm), 0);
    await tap(toggleAt(60, 160));
    await tap(message('120'));
    await tap(buttonAt(360, 220));
    audio(4200);
    await ask();
    expect(read(bpm), 240, reason: 'glided to 240');
    expect(whole(at('.i', 60, 550)), (read(beat) / 4).floor(), reason: 'bar');
    await tap(message('stop'));
    await close();

    // ── tempo: quarter notes round a bar, the tempo, the division ───────────
    at = await open(
      '.tempo',
      slug: 'tempo',
      notes: 5,
      heading: 'sends 0 1 2 3 on every quarter note',
    );
    final count = at('.i', 60, 360);
    final steps = at('.i', 340, 460);
    await tap(toggleAt(60, 160));
    expect((value(count), value(at('.i', 200, 460))), ('0', '1'));
    final seen = <int>[];
    for (var i = 0; i < 16; i++) {
      audio(125);
      if (seen.isEmpty || seen.last != whole(count)) seen.add(whole(count));
    }
    expect(seen, [0, 1, 2, 3, 0], reason: 'quarter notes round a bar');
    expect(value(at('.i', 200, 460)), '2', reason: 'a second bar');
    expect(await shown('.i', 340, 460), whole(steps), reason: 'on screen');
    await tap(message('16'));
    var before = whole(steps);
    audio(1000);
    expect(whole(steps) - before, inInclusiveRange(7, 9), reason: '16ths');
    await tap(message('60'));
    before = whole(steps);
    audio(1000);
    expect(whole(steps) - before, inInclusiveRange(3, 5), reason: 'at 60');
    await tap(toggleAt(60, 160));
    before = whole(steps);
    audio(500);
    expect(whole(steps), before, reason: 'off stops the count');
    await close();

    // ── timepoint: four beats from now, a typed beat ────────────────────────
    at = await open(
      '.timepoint',
      slug: 'timepoint',
      notes: 5,
      heading: 'bangs once when the domain clock',
    );
    final fired = at('.i', 220, 490);
    final target = at('.f', 220, 320);
    await tap(buttonAt(220, 160));
    audio(3500);
    expect(value(fired), '0', reason: 'not yet');
    audio(800);
    expect(value(fired), '1', reason: 'four beats later');
    expect(read(at('.f', 360, 490)), closeTo(read(target), 0.1));
    // Type a beat a second ahead of the clock into the box above timepoint.
    await tap(toggleAt(60, 160));
    audio(300);
    await wait(400);
    await tap(toggleAt(60, 160));
    final now = read(at('.f', 60, 320));
    final field = find.descendant(
      of: nodeAt('.f', 220, 320),
      matching: find.descendant(
        of: find.byType(NumberNodeBody),
        matching: find.byType(TextField),
      ),
    );
    await tester.enterText(field, (now + 1.5).toStringAsFixed(2));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(read(target), closeTo(now + 1.5, 0.01));
    audio(1000);
    expect(value(fired), '1');
    audio(1000);
    expect(value(fired), '2', reason: 'the typed beat');
    await close();

    // ── setclock: two clocks, a metro on each, a delay in beats ─────────────
    at = await open(
      '.setclock',
      slug: 'setclock',
      notes: 6,
      heading: 'runs from the moment the patch opens',
    );
    final left = at('.i', 60, 470);
    final right = at('.i', 300, 470);
    await tap(toggleAt(60, 300));
    expect((value(left), value(right)), ('1', '1'), reason: 'at once');
    audio(1100);
    expect(whole(left), 2, reason: 'a beat a second on slow');
    expect(whole(right), inInclusiveRange(4, 6), reason: '240 on fast');
    await tap(message('0'));
    before = whole(left);
    audio(1500);
    expect(whole(left), before, reason: 'slow at 0 stops its metro');
    await tap(message('60'));
    await tap(toggleAt(60, 300));
    final arrived = at('.i', 60, 730);
    await tap(buttonAt(60, 560));
    audio(3700);
    expect(value(arrived), '0', reason: 'four beats at 60');
    audio(600);
    expect(value(arrived), '1');
    expect(await shown('.i', 60, 730), 1, reason: 'on screen');
    await close();

    // ── when: beat and tempo on any input ───────────────────────────────────
    at = await open(
      '.when',
      slug: 'when',
      notes: 5,
      heading: 'reports the beat position and tempo',
    );
    final whenBeat = at('.f', 300, 340);
    await tap(buttonAt(300, 160));
    expect(read(at('.f', 440, 340)), 0, reason: 'stopped when it opens');
    final from = read(whenBeat);
    await tap(toggleAt(60, 160));
    audio(1000);
    await tap(buttonAt(300, 160));
    expect(read(at('.f', 440, 340)), 120);
    expect(read(whenBeat), closeTo(from + 2, 0.1));
    audio(500);
    await tap(message('42'));
    expect(read(whenBeat), closeTo(from + 3, 0.1), reason: 'any input asks');
    await tap(toggleAt(60, 160));
    await tap(buttonAt(300, 440));
    expect(value(at('.i', 300, 660)), '0', reason: 'nowhere: no answer');
    await close();

    // ── translate: ms to beats, ticks and Hz, a tempo change, note values ───
    at = await open(
      '.translate',
      slug: 'translate',
      notes: 5,
      heading: 'converts a time value from one format',
    );
    await tap(message('500'));
    expect(
      (read(at('.f', 60, 480)), read(at('.f', 270, 480))),
      (1, 480),
      reason: 'half a second at 120',
    );
    expect(await shown('.f', 480, 480), 2, reason: '2 Hz on screen');
    await tap(message('240'));
    audio(20);
    await tap(buttonAt(420, 300));
    expect(read(at('.f', 60, 480)), 2, reason: 'converted again at 240');
    await tap(message('4n'));
    expect(read(at('.f', 60, 680)), 250, reason: 'a quarter note at 240');
    await tap(message('120'));
    audio(20);
    await tap(message('4nd'));
    expect(read(at('.f', 60, 680)), 750);
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
