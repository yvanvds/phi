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
import 'package:phi/surfaces/patcher/nodes/slider_node_body.dart';
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

/// End-to-end proof of the **audio basics tutorials** (issue #494)
/// through the real [PhiApp]: real rail navigation, fonts and layout, the real
/// asset bundle and the real patcher engine ([RealPatcherGateway] on an
/// offline libyse session). Only the audio device and MIDI are fakes.
///
/// The `~sine`, `~saw`, `~noise`, `~line`, `~adc`/`~dac`, signal arithmetic,
/// `~lp`/`~hp` and `~bp`/`~vcf` tutorials are opened from the palette's
/// Tutorials tab. The test checks that the notes render and nothing overlaps,
/// then plays the patches with real taps and drags, and listens on master: a
/// tutorial is mounted on the offline session's master bus, so rendering a
/// few blocks and reading the master meter tells whether the user would hear
/// what the notes promise.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every audio basics tutorial opens from the Tutorials '
      'tab and sounds on master the way its notes say', (tester) async {
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
          newLocationPath: '/projects/audio-basics.phi',
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

    // The mean of the per-block master peaks over [blocks] blocks, after 20
    // blocks for a change to settle. A stable level for noise, filters and
    // sweeps, where the single loudest block varies from run to run (#525).
    double level([int blocks = 400]) {
      loudness(20);
      var sum = 0.0;
      for (var i = 0; i < blocks; i++) {
        sum += loudness(1);
      }
      return sum / blocks;
    }

    // A press at [from], dragged through to [to] in two steps.
    Future<void> drag(Offset from, Offset to) async {
      final pointer = await tester.startGesture(from);
      await tester.pump();
      await pointer.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await pointer.moveTo(to);
      await tester.pump();
      await pointer.up();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // Drags the slider at ([x], [y]) from its middle to [fraction] of its
    // height (0 the bottom, 1 the top).
    Future<void> slide(double x, double y, double fraction) async {
      final body = tester.getRect(
        find.descendant(
          of: nodeAt('.slider', x, y),
          matching: find.byType(SliderNodeBody),
        ),
      );
      await drag(
        body.center,
        Offset(body.center.dx, body.bottom - fraction * body.height),
      );
    }

    // ── ~sine: on, a set frequency, a dragged slider, beating ───────────────
    var at = await open(
      '~sine',
      slug: 'sine',
      notes: 5,
      heading: 'A ~sine is an oscillator',
    );
    expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
    await tap(toggleAt(170, 260));
    final sine = loudness();
    expect(sine, greaterThan(0.05), reason: 'the left sine on master');
    await tap(message('440.'));
    expect(read(at('.f', 60, 200)), 440);
    await slide(300, 140, 0.9);
    expect(read(at('.f', 60, 200)), greaterThan(495), reason: 'dragged up');
    await tap(message('220.'));
    await tap(toggleAt(410, 380));
    expect(loudness(400), greaterThan(1.8 * sine), reason: 'beats swell');
    await close();

    // ── ~saw: the saw and the sine, a dragged cutoff ────────────────────────
    at = await open(
      '~saw',
      slug: 'saw',
      notes: 5,
      heading: 'A ~saw plays a sawtooth wave',
    );
    expect(read(at('.f', 340, 360)), closeTo(4050, 1e-3), reason: 'loadmess');
    await tap(toggleAt(60, 140));
    final bright = level();
    expect(bright, greaterThan(0.05));
    await slide(340, 140, 0.05);
    expect(read(at('.f', 340, 360)), lessThan(1000), reason: 'dragged down');
    expect(level(), lessThan(bright), reason: 'darker, quieter');
    await tap(toggleAt(60, 140));
    await tap(toggleAt(200, 140));
    expect(loudness(), greaterThan(0.05), reason: 'the sine');
    await close();

    // ── ~noise: raw, lowpass, bandpass, the level slider ────────────────────
    at = await open(
      '~noise',
      slug: 'noise',
      notes: 5,
      heading: 'A ~noise sends random samples',
    );
    expect(loudness(), lessThan(1e-4));
    await tap(toggleAt(60, 140));
    final hiss = level();
    expect(hiss, greaterThan(0.01));
    await slide(480, 190, 0);
    expect(read(at('.slider', 480, 190)), lessThan(0.05));
    expect(level(), lessThan(0.15 * hiss), reason: 'turned down');
    await slide(480, 190, 0.5);
    await tap(toggleAt(60, 140));
    await tap(toggleAt(200, 140));
    expect(level(), inExclusiveRange(0, hiss), reason: 'the lowpass');
    await tap(toggleAt(200, 140));
    await tap(toggleAt(340, 140));
    expect(level(), inExclusiveRange(0, hiss), reason: 'the bandpass');
    await close();

    // ── ~line: a fade in, a held ramp, quick fades, the unpacked list ───────
    at = await open(
      '~line',
      slug: 'sig-line',
      notes: 5,
      heading: 'A ~line moves a signal to a target',
    );
    expect(loudness(), lessThan(1e-4), reason: 'starts at 0');
    await tap(message('1.'));
    final full = loudness(1200);
    expect(full, greaterThan(0.1), reason: 'faded in');
    await tap(message('0.'));
    loudness(300);
    await tap(message('stop'));
    final held = loudness(5);
    expect(held, inExclusiveRange(0.1 * full, 0.95 * full));
    expect(loudness(300), closeTo(held, 0.02 * full), reason: 'held');
    await tap(message('10.'));
    await tap(message('0.'));
    loudness(40);
    expect(loudness(5), lessThan(0.01 * full), reason: 'a quick fade');
    await tap(find.byType(PatchBangSquare));
    loudness(400);
    expect(loudness(20), closeTo(0.25 * full, 0.02 * full), reason: 'unpack');
    await close();

    // ── ~adc / ~dac: two dacs sum, the rest stays silent ────────────────────
    at = await open(
      '~dac',
      slug: 'adc-dac',
      notes: 5,
      heading: 'A ~dac is the patch',
    );
    expect(read(at('.slider', 180, 470)), closeTo(1, 1e-6));
    expect(
      loudness(),
      lessThan(1e-4),
      reason: 'the noise reaches no dac, and adc is silent as a source',
    );
    await tap(toggleAt(60, 140));
    final one = loudness(400);
    expect(one, greaterThan(0.05));
    await tap(toggleAt(300, 140));
    expect(loudness(400), greaterThan(1.5 * one), reason: 'the dacs sum');
    await close();
    await open(
      '~adc',
      slug: 'adc-dac',
      notes: 5,
      heading: 'A ~dac is the patch',
    );
    await close();

    // ── signal arithmetic: a gain, limits, ring modulation ──────────────────
    at = await open(
      '~*',
      slug: 'signal-math',
      notes: 5,
      heading: 'These work sample by sample',
    );
    expect(loudness(), lessThan(1e-4));
    await slide(440, 140, 1);
    final unit = loudness();
    expect(unit, greaterThan(0.05), reason: 'a sine times a number');
    await tap(message('0.2'));
    expect(loudness(), closeTo(0.2 * unit, 0.02 * unit), reason: 'clipped');
    await tap(message('1'));
    expect(loudness(), closeTo(unit, 0.02 * unit), reason: 'an int opens it');
    await slide(440, 140, 0);
    await tap(toggleAt(330, 200));
    await tap(message('300.'));
    expect(loudness(400), closeTo(unit, 0.1 * unit), reason: 'ring');
    await close();
    for (final type in ['~+', '~-', '~/', '~clip']) {
      await open(
        type,
        slug: 'signal-math',
        notes: 5,
        heading: 'These work sample by sample',
      );
      await close();
    }

    // ── ~lp / ~hp: a swept cutoff, the two halves ───────────────────────────
    at = await open(
      '~lp',
      slug: 'lp-hp',
      notes: 4,
      heading: 'A ~lp lets the frequencies below',
    );
    expect(read(at('.f', 340, 360)), closeTo(1000, 1e-3), reason: 'loadmess');
    await tap(toggleAt(60, 140));
    final lp1000 = level();
    expect(lp1000, greaterThan(0.01));
    await slide(340, 140, 0.02);
    final rumble = level();
    expect(rumble, lessThan(0.5 * lp1000), reason: 'a low cutoff');
    await tap(toggleAt(60, 140));
    await tap(toggleAt(200, 140));
    expect(level(), greaterThan(3 * rumble), reason: 'hp keeps the rest');
    await close();
    await open('~hp', slug: 'lp-hp', notes: 4, heading: 'A ~lp lets');
    await close();

    // ── ~bp / ~vcf: a band over noise, the Q, a resonant sweep ──────────────
    at = await open(
      '~bp',
      slug: 'bp-vcf',
      notes: 5,
      heading: 'A ~bp passes a band',
    );
    expect(loudness(), lessThan(1e-4));
    await tap(toggleAt(60, 140));
    final wide = level();
    expect(wide, greaterThan(0.01));
    await tap(message('10.'));
    expect(level(), inExclusiveRange(0, wide), reason: 'Q 10');
    await tap(message('1.'));
    await tap(toggleAt(60, 140));
    await tap(toggleAt(60, 400));
    // Each level spans one 4 s cycle of the 0.25 Hz sweep, so where the
    // sweep stands does not matter.
    final sweep = (4 * 48000 / System.blockSize).ceil();
    final soft = level(sweep);
    expect(soft, greaterThan(0.01), reason: 'the vcf sweeps');
    await tap(message('20.'));
    expect(level(sweep), inExclusiveRange(0, soft), reason: 'sharper');
    await close();
    await open('~vcf', slug: 'bp-vcf', notes: 5, heading: 'A ~bp passes');
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
