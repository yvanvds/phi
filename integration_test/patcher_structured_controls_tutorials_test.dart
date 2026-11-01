import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_function_graph.dart';
import 'package:phi/design/widgets/patcher/patch_keyboard.dart';
import 'package:phi/design/widgets/patcher/patch_matrix_grid.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_nodes_field.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_preset_grid.dart';
import 'package:phi/design/widgets/patcher/patch_staff.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/domain/patcher/nodes_view.dart';
import 'package:phi/domain/patcher/preset_grid.dart';
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

/// End-to-end proof of the **structured control tutorials** (issue #493)
/// through the real [PhiApp]: real rail navigation, fonts and layout, the real
/// asset bundle and the real patcher engine ([RealPatcherGateway] on an
/// offline libyse session). Only the audio device and MIDI are fakes.
///
/// The `.matrixctrl`, `.function`, `.nodes`, `.preset`, `.kslider` and
/// `.nslider` tutorials are opened from the palette's Tutorials tab. The test
/// checks that the notes render and nothing overlaps, then plays the controls
/// with real taps and drags and reads the result back from the engine, the
/// way the notes tell the user to.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder message(String text) => find.descendant(
    of: find.byType(PatchMessageBox),
    matching: find.text(text),
  );

  testWidgets('patcher: every structured control tutorial opens from the '
      'Tutorials tab and its controls do what its notes say', (tester) async {
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
          newLocationPath: '/projects/structured-controls.phi',
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

    // Every widget [f] finds, top to bottom on the canvas — or left to right
    // with [across].
    List<Finder> inOrder(Finder f, {bool across = false}) {
      double key(Finder e) =>
          across ? tester.getTopLeft(e).dx : tester.getTopLeft(e).dy;
      return [for (var i = 0; i < f.evaluate().length; i++) f.at(i)]
        ..sort((a, b) => key(a).compareTo(key(b)));
    }

    // The numbers in a multi-value control's state or a list.
    List<double> numbers(int id) => [
      for (final t in value(id).split(' ')) double.parse(t),
    ];

    double read(int id) => double.parse(value(id));

    // Taps at [at] and lets the body's poll run.
    Future<void> tapAt(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
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

    // ── .matrixctrl: a patchbay into router, a step grid ────────────────────
    var at = await open(
      '.matrixctrl',
      slug: 'matrixctrl',
      notes: 7,
      heading: 'A matrixctrl is a grid of cells',
    );
    expect(find.byType(PatchMatrixGrid), findsNWidgets(2));
    Finder gridOf(int columns) => find.byWidgetPredicate(
      (w) => w is PatchMatrixGrid && w.columns == columns,
    );
    Offset cellAt(int columns, int rows, int column, int row) {
      final box = tester.getRect(gridOf(columns));
      return box.topLeft +
          Offset(
            box.width * (column + 0.5) / columns,
            box.height * (row + 0.5) / rows,
          );
    }

    // The patchbay: column 0 row 1 sends 100 to the right output.
    await tapAt(cellAt(2, 2, 0, 1));
    expect(numbers(at('.l', 420, 140)), [0, 1, 1], reason: 'the cell form');
    await tap(message('100'));
    expect(value(at('.i', 420, 360)), '100');
    expect(value(at('.i', 330, 360)), '0');
    // The step grid: a hit on step 3, row 0.
    final steps = at('.matrixctrl', 60, 420);
    await tapAt(cellAt(16, 4, 3, 0));
    expect(numbers(at('.l', 60, 500)), [3, 0, 1]);
    expect(
      tester.widget<PatchMatrixGrid>(gridOf(16)).values[3 * 4],
      1,
      reason: 'column 3, row 0 lit',
    );
    // Play: the metro fetches column 0 at once.
    await tap(find.byType(PatchToggleSquare));
    expect(int.parse(value(at('.i', 190, 290))), inInclusiveRange(0, 15));
    expect(numbers(at('.l', 200, 500)), hasLength(4), reason: 'a column');
    await tap(find.byType(PatchToggleSquare));
    await tap(message('clear'));
    expect(
      numbers(steps).every((v) => v == 0),
      isTrue,
      reason: 'clear empties the grid',
    );
    await close();

    // ── .function: the saved envelope, a query, a drawn point, dump ─────────
    at = await open(
      '.function',
      slug: 'function',
      notes: 6,
      heading: 'A function holds breakpoints',
    );
    PatchFunctionGraph graph() =>
        tester.widget<PatchFunctionGraph>(find.byType(PatchFunctionGraph));
    expect(graph().positions, hasLength(4), reason: 'saved with the patch');
    await tap(find.byType(PatchBangSquare));
    expect(numbers(at('.l', 150, 340)), [0, 0, 1, 30, 0.5, 90, 0, 480]);
    await tap(message('15'));
    expect(read(at('.f', 60, 340)), closeTo(0.5, 1e-6));
    // Click empty space high in the release: a fifth point.
    final plot = tester.getRect(find.byType(PatchFunctionGraph));
    const inset = PatchFunctionGraph.inset;
    await tapAt(
      plot.topLeft +
          Offset(
            inset + 0.8 * (plot.width - 2 * inset),
            inset + 0.2 * (plot.height - 2 * inset),
          ),
    );
    expect(graph().positions, hasLength(5), reason: 'a click adds a point');
    await tap(message('dump'));
    expect(numbers(at('.l', 300, 340)).first, 4, reason: 'the last index');
    await close();

    // ── .nodes: drag the cursor, the middle is silent ───────────────────────
    at = await open(
      '.nodes',
      slug: 'nodes',
      notes: 5,
      heading: 'A nodes field holds circles',
    );
    final weights = at('.l', 60, 440);
    expect(
      tester.widget<PatchNodesField>(find.byType(PatchNodesField)).nodes,
      hasLength(4),
      reason: 'loadmess laid out four nodes',
    );
    Offset fieldAt(double x, double y) {
      final box = tester.getRect(find.byType(PatchNodesField));
      final (px, py) = NodesView(
        width: box.width,
        height: box.height,
      ).toPixel(x, y);
      return box.topLeft + Offset(px, py);
    }

    await drag(fieldAt(0.3, 0.3), fieldAt(0.48, 0.25));
    final w = numbers(weights);
    expect(w, hasLength(4));
    expect(w.reduce((a, b) => a + b), closeTo(1, 1e-4), reason: 'sum to 1');
    expect(w[0], greaterThan(0));
    expect(w[1], greaterThan(0), reason: 'between the lower two nodes');
    // The two buttons beside the field, below the one above loadmess: left
    // 0.5 0.25, right the middle.
    final pair = inOrder(find.byType(PatchBangSquare)).sublist(1)
      ..sort(
        (a, b) => tester.getTopLeft(a).dx.compareTo(tester.getTopLeft(b).dx),
      );
    await tap(pair.first);
    expect(numbers(weights), [0.5, 0.5, 0, 0]);
    await tap(pair.last);
    expect(numbers(weights), [0, 0, 0, 0], reason: 'inside no node');
    await close();

    // ── .preset: shipped slots, an empty slot, Shift+click stores ───────────
    at = await open(
      '.preset',
      slug: 'preset',
      notes: 5,
      heading: 'A preset keeps the values',
    );
    final note = at('.i', 250, 140);
    PatchPresetGrid bank() =>
        tester.widget<PatchPresetGrid>(find.byType(PatchPresetGrid));
    expect(bank().stored, {0, 1, 2}, reason: 'the slots came with the patch');
    Offset slot(int n) {
      final box = tester.getRect(find.byType(PatchPresetGrid));
      final grid = PresetGrid(slots: 8, width: box.width, height: box.height);
      final (x, y) = grid.originOf(n);
      return box.topLeft +
          Offset(x + grid.cellWidth / 2, y + grid.cellHeight / 2);
    }

    await tapAt(slot(1));
    expect(value(note), '57');
    expect(value(at('.t', 60, 140)), 'on');
    expect(value(at('.i', 60, 740)), '1', reason: 'the recalled slot');
    await tap(message('5'));
    expect((value(note), value(at('.i', 60, 740))), ('57', '1'));
    await tap(message('0'));
    expect(value(note), '45');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(slot(4));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(value(at('.i', 190, 740)), '4', reason: 'Shift+click stored');
    expect(bank().stored, {0, 1, 2, 4});
    await tap(message('2'));
    expect(value(note), '52');
    await tapAt(slot(4));
    expect(value(note), '45', reason: 'slot 4 holds what slot 0 set');
    await tap(find.byType(PatchToggleSquare));
    expect(value(at('.t', 60, 140)), 'off');
    await close();

    // ── .kslider: a pressed key, a cable note, a release ────────────────────
    at = await open(
      '.kslider',
      slug: 'kslider',
      notes: 5,
      heading: 'A kslider is a piano keyboard',
    );
    PatchKeyboard keyboard() =>
        tester.widget<PatchKeyboard>(find.byType(PatchKeyboard));
    Offset keyAt(int pitch, double y) {
      final box = tester.getRect(find.byType(PatchKeyboard));
      final b = keyboard().layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * y);
    }

    final pitch = at('.i', 60, 350);
    final velocity = at('.i', 260, 350);
    await tapAt(keyAt(62, 0.85));
    expect(value(pitch), '62');
    expect(value(velocity), '0', reason: 'letting go released it');
    await tap(message('60'));
    expect(keyboard().held.keys, [60], reason: 'a cable note lights its key');
    expect((value(pitch), value(velocity)), ('60', '100'));
    // The button on the top row, left: pack 60 0.
    final row = inOrder(find.byType(PatchBangSquare), across: true);
    await tap(row.first);
    expect(keyboard().held, isEmpty, reason: 'velocity 0 releases it');
    await tap(message('40'));
    await tap(message('64'));
    expect((value(pitch), value(velocity)), ('64', '40'));
    await tap(row.last);
    expect((value(pitch), value(velocity)), ('67', '110'));
    await close();

    // ── .nslider: sharps against flats, a dragged note ──────────────────────
    at = await open(
      '.nslider',
      slug: 'nslider',
      notes: 5,
      heading: 'An nslider shows one note',
    );
    expect(find.byType(PatchStaff), findsNWidgets(2));
    await tap(message('61'));
    expect((value(at('.i', 60, 420)), value(at('.i', 140, 420))), ('61', '1'));
    expect(
      (value(at('.i', 240, 420)), value(at('.i', 320, 420))),
      ('61', '-1'),
    );
    await tap(find.byType(PatchBangSquare));
    expect(value(at('.i', 140, 420)), '-1', reason: 'pack 61 -1 respells');
    await tap(message('90'));
    expect(value(at('.i', 240, 420)), '72', reason: 'the right staff range');
    // Drag the left staff's note down: a lower pitch.
    final staff = inOrder(find.byType(PatchStaff), across: true).first;
    final centre = tester.getCenter(staff);
    await drag(centre, centre + const Offset(0, 40));
    expect(int.parse(value(at('.i', 60, 420))), lessThan(90));
    await tap(find.byType(PatchToggleSquare));
    expect(value(at('.t', 200, 480)), 'on');
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
