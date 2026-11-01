import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_menu_box.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_radio_group.dart';
import 'package:phi/design/widgets/patcher/patch_range_bar.dart';
import 'package:phi/design/widgets/patcher/patch_slider_bank.dart';
import 'package:phi/design/widgets/patcher/patch_tab_strip.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/design/widgets/patcher/patch_xy_pad.dart';
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

/// End-to-end proof of the **selection and slider control tutorials** (issue
/// #492)
/// through the real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// The shared `.umenu` / `.radiogroup` / `.tab` tutorial and those of
/// `.rslider`, `.xyslider` and `.multislider` are opened from the palette's
/// Tutorials tab. The test checks that the notes render and nothing overlaps,
/// then plays the controls with real taps and drags and reads the result back
/// from the engine, the way the notes tell the user to.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every selection and slider control tutorial opens from '
      'the Tutorials tab and its controls do what its notes say', (
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
          newLocationPath: '/projects/selection-slider-controls.phi',
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
      // Search for the type: the browser builds only the entries near its
      // viewport, so a long list leaves later ones unbuilt (#524).
      final search = find.byKey(PatchTutorialBrowser.searchKey);
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(search, type);
      await tester.pumpAndSettle();
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

    // Every widget [f] finds, top to bottom on the canvas — or left to right
    // with [across].
    List<Finder> inOrder(Finder f, {bool across = false}) {
      double key(Finder e) =>
          across ? tester.getTopLeft(e).dx : tester.getTopLeft(e).dy;
      return [for (var i = 0; i < f.evaluate().length; i++) f.at(i)]
        ..sort((a, b) => key(a).compareTo(key(b)));
    }

    // The highest of the widgets [f] finds on the canvas.
    Finder topmost(Finder f) {
      final all = [for (var i = 0; i < f.evaluate().length; i++) f.at(i)]
        ..sort(
          (a, b) => tester.getTopLeft(a).dy.compareTo(tester.getTopLeft(b).dy),
        );
      return all.first;
    }

    // The numbers in a multi-value control's state or a list.
    List<double> numbers(int id) => [
      for (final t in value(id).split(' ')) double.parse(t),
    ];

    // ── .umenu / .radiogroup / .tab: one protocol, three outlets, multi ─────
    var at = await open(
      '.umenu',
      slug: 'menus',
      notes: 7,
      heading: 'These three are one object drawn three ways',
    );
    expect(find.byType(PatchMenuBox), findsOneWidget);
    expect(find.byType(PatchRadioGroup), findsNWidgets(2));
    expect(find.byType(PatchTabStrip), findsOneWidget);
    final single = find.byWidgetPredicate(
      (w) => w is PatchRadioGroup && !w.multi,
    );
    final checks = find.byWidgetPredicate(
      (w) => w is PatchRadioGroup && w.multi,
    );
    Set<int> tabsLit() =>
        tester.widget<PatchTabStrip>(find.byType(PatchTabStrip)).selected;
    await tap(message('2'));
    expect(tester.widget<PatchRadioGroup>(single).selected, {2});
    expect(tabsLit(), {2}, reason: 'a number selects in all three');
    expect(value(at('.i', 60, 310)), '2');
    expect(
      find.descendant(
        of: find.byType(PatchListBox),
        matching: find.text('noise'),
      ),
      findsOneWidget,
      reason: 'the name outlet',
    );
    await tap(message('saw'));
    expect(value(at('.umenu', 60, 200)), '1', reason: 'a name selects');
    expect(tabsLit(), {1});
    // Pick from the drop-down itself: the boxes under it follow.
    final menuBox = tester.getRect(find.byType(PatchMenuBox));
    await tap(find.byType(PatchMenuBox));
    // The list opens under the box, one 24 px row per item: sine first.
    await tester.tapAt(menuBox.bottomLeft + const Offset(12, 4 + 12));
    await tester.pumpAndSettle();
    expect(value(at('.i', 60, 310)), '0');
    expect(value(at('.radiogroup', 220, 200)), '1', reason: 'its own object');
    // A tab click changes only the tab.
    await tap(
      find.descendant(
        of: find.byType(PatchTabStrip),
        matching: find.byKey(PatchTabStrip.itemKey(2)),
      ),
    );
    expect(value(at('.tab', 360, 200)), '2');
    expect(value(at('.umenu', 60, 200)), '0');
    // multi: tick boxes, toggle by number, set them all with a list.
    final flags = at('.l', 300, 570);
    Finder check(int i) => find.descendant(
      of: checks,
      matching: find.byKey(PatchRadioGroup.itemKey(i)),
    );
    await tap(check(0));
    await tap(check(2));
    expect(numbers(flags), [1, 0, 1]);
    expect(tester.widget<PatchRadioGroup>(checks).selected, {0, 2});
    await tap(message('1'));
    expect(numbers(flags), [1, 1, 1], reason: 'a number toggles');
    expect(value(at('.i', 200, 570)), '1', reason: 'the item that changed');
    // The lower of the two buttons sits above pack 1 0 1.
    final buttons = inOrder(find.byType(PatchBangSquare));
    await tap(buttons.last);
    expect(numbers(flags), [1, 0, 1], reason: 'pack sends a whole list');
    await close();

    // The index points all three types at the one tutorial.
    for (final type in ['.radiogroup', '.tab']) {
      // Search for the type: the browser builds only the entries near its
      // viewport, so a long list leaves later ones unbuilt (#524).
      final search = find.byKey(PatchTutorialBrowser.searchKey);
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(search, type);
      await tester.pumpAndSettle();
      final entry = find.byKey(PatchTutorialBrowser.entryKey(type));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(library.tutorial?.slug, 'menus', reason: type);
      await close();
    }

    // ── .rslider: a silent end, sorted ends, a press, a random range ────────
    at = await open(
      '.rslider',
      slug: 'rslider',
      notes: 5,
      heading: 'An rslider holds two ends',
    );
    final low = at('.f', 60, 380);
    final high = at('.f', 150, 380);
    double read(int id) => double.parse(value(id));
    await tap(message('48'));
    expect(read(high), 0, reason: 'the right inlet is silent');
    await tap(message('84'));
    expect((read(low), read(high)), (48.0, 84.0));
    await tap(topmost(find.byType(PatchBangSquare)));
    expect(
      (read(low), read(high)),
      (40.0, 90.0),
      reason: 'the list 90 40 comes out sorted',
    );
    await tap(message('60'));
    expect(read(low), 60.0, reason: 'set 0 60');
    // Press near the top of the bar: the nearer end, high, jumps there.
    final bar = tester.getRect(find.byType(PatchRangeBar));
    await tester.dragFrom(
      bar.topCenter + const Offset(0, 4),
      const Offset(0, 2),
    );
    await tester.pumpAndSettle();
    expect(read(high), greaterThan(92));
    expect(read(low), 60.0);
    final top = read(high);
    final pick = inOrder(find.byType(PatchBangSquare));
    for (var i = 0; i < 5; i++) {
      await tap(pick.last);
      expect(read(at('.f', 60, 650)), inInclusiveRange(60, top));
    }
    await close();

    // ── .xyslider: one drag, two parameters; a silent y ─────────────────────
    at = await open(
      '.xyslider',
      slug: 'xyslider',
      notes: 5,
      heading: 'An xyslider is a pad',
    );
    final x = at('.f', 60, 360);
    final y = at('.f', 150, 360);
    await tap(find.byType(PatchToggleSquare));
    expect(value(at('.t', 220, 440)), 'on');
    final pad = tester.getRect(find.byType(PatchXyPad));
    await tester.dragFrom(
      pad.bottomLeft + const Offset(4, -4),
      Offset(pad.width - 8, -(pad.height - 8)),
    );
    await tester.pumpAndSettle();
    expect(read(x), greaterThan(900), reason: 'x to the right');
    expect(read(y), greaterThan(4500), reason: 'y to the top');
    await tap(message('300'));
    expect(read(x), 300.0);
    final before = read(y);
    await tap(message('2000'));
    expect(read(y), before, reason: 'the right inlet is silent');
    await tap(find.byType(PatchBangSquare));
    expect(read(y), 2000.0);
    await tap(message('4000'));
    expect(read(y), 4000.0, reason: 'set 1 4000');
    expect(numbers(at('.l', 240, 360)), [300, 4000], reason: 'the pair');
    await tap(find.byType(PatchToggleSquare));
    await close();

    // ── .multislider: a loaded pattern, a drawn cell, fill and resize ───────
    at = await open(
      '.multislider',
      slug: 'multislider',
      notes: 5,
      heading: 'A multislider holds a row of values',
    );
    final bank = at('.multislider', 60, 260);
    List<double> bars() =>
        tester.widget<PatchSliderBank>(find.byType(PatchSliderBank)).values;
    expect(numbers(bank), [0, 3, 7, 10, 12, 10, 7, 3], reason: 'loadmess');
    expect(bars(), hasLength(8));
    // Press the top of the first bar: that cell goes to the maximum.
    final cells = tester.getRect(find.byType(PatchSliderBank));
    await tester.tapAt(cells.topLeft + Offset(cells.width / 16, 2));
    await tester.pumpAndSettle();
    expect(numbers(bank).first, greaterThan(22));
    await tap(message('12'));
    expect(numbers(bank), List.filled(8, 12.0), reason: 'a number fills');
    // The two buttons on the top row: loadmess (left) and pack (right).
    final row = inOrder(find.byType(PatchBangSquare), across: true);
    await tap(row.last);
    expect(numbers(bank), [0, 4, 7, 12], reason: 'a list resizes');
    expect(bars(), hasLength(4));
    await tap(row.first);
    expect(numbers(bank), [0, 3, 7, 10, 12, 10, 7, 3]);
    // Start the sequence: the metro fetches cell 0 at once, C3 + 0.
    await tap(find.byType(PatchToggleSquare));
    expect(int.parse(value(at('.i', 400, 440))), inInclusiveRange(0, 7));
    expect(read(at('.f', 170, 470)) - 48, isIn([0, 3, 7, 10, 12]));
    await tap(find.byType(PatchToggleSquare));
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
