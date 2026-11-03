import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/subpatch/subpatch_window_view.dart';
import 'package:yse/yse.dart';

import '../../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../../test/domain/project/test_doubles/fake_journal_store.dart';
import '../../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../../test/domain/project/test_doubles/fake_project_store.dart';
import '../../test/engine/test_doubles/fake_midi_gateway.dart';
import '../../test/engine/test_doubles/fake_yse_gateway.dart';
import '../../test/surfaces/patcher/test_support/until_window_active.dart';
import 'native_keyboard.dart';
import 'native_windows_test_binding.dart';
import 'text_input_view_rule_check.dart';

/// End-to-end proof of abstractions (issue #553), through the real [PhiApp], a
/// second **native** window and the real patcher engine ([RealPatcherGateway]
/// over an offline libyse session). Only the audio device, MIDI and the project
/// store are fakes.
///
/// The performer builds `~sine` → `~* 0.5` → `~dac`, encapsulates the `~*` and
/// picks *make abstraction*: the box is now an instance of a new patch. Typing
/// that patch's address into the object box makes a second instance, wired from
/// a second sine into the same dac, and both are heard on master. *Open
/// definition* shows the patch in a window of its own. Deleting the `~*` there
/// empties both instances and silences both, and `Ctrl+Z` in that window brings
/// all of it back. Saved and reopened, both boxes are still instances, they
/// sound, and a change to the definition still reaches them.
void main() {
  NativeWindowsTestBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: two instances of one patch sound, follow an edit made '
      'in its own window, undo with it, and survive a save → reopen', (
    tester,
  ) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);
    final textInput = TextInputViewRuleCheck(
      tester.binding.defaultBinaryMessenger,
    );
    addTearDown(textInput.dispose);
    final keyboard = NativeKeyboard(tester, textInput);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));

    const dir = '/projects/abstraction.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    late PhiEngine engine;
    late RealPatcherGateway gateway;

    Future<
      ({
        PhiEngine engine,
        ProjectController project,
        SessionState session,
        AppSettingsController settings,
      })
    >
    launch(String key, {String? newPath}) async {
      final g = RealPatcherGateway();
      final e = PhiEngine(
        FakeYseGateway(),
        patcherGateway: g,
        midiGateway: FakeMidiGateway(),
        telemetryInterval: const Duration(milliseconds: 20),
      );
      final session = SessionState();
      final appSettings = AppSettingsController(settings);
      final project = ProjectController(
        session: session,
        settings: appSettings,
        storeFactory: (_) => store,
        journalStoreFactory: (_) => journal,
        seedRegistry: seedDefaultProject,
        autosaveIntervalOverride: const Duration(hours: 1),
      );
      await tester.pumpWidget(
        PhiApp(
          key: ValueKey(key),
          engine: e,
          session: session,
          projectController: project,
          directoryPicker: FakeProjectDirectoryPicker(newLocationPath: newPath),
          autoStartProject: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(railFor(SurfaceId.patcher));
      await tester.pumpAndSettle();
      engine = e;
      gateway = g;
      return (
        engine: e,
        project: project,
        session: session,
        settings: appSettings,
      );
    }

    PatcherController editor() => engine.patcher;

    // A definition's window has no scope either, so the main canvas is the one
    // driving the open patch.
    Finder mainCanvas() => find.byWidgetPredicate(
      (w) => w is PatcherCanvas && identical(w.controller, editor()),
    );
    Finder windowCanvas() => find.byKey(SubpatchWindowView.canvasKey);

    PatcherController editorOf(Finder canvas) =>
        tester.widget<PatcherCanvas>(canvas).controller;

    Finder nodeView(Finder canvas, PatchNodeId id) => find.descendant(
      of: canvas,
      matching: find.byWidgetPredicate(
        (w) => w is PatcherNodeView && w.node.id == id,
      ),
    );

    FlutterView viewOf(Finder f) => tester.viewOf(f);

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

    // libyse sets a new sound up on a worker thread in wall-clock time, while
    // an offline render runs far ahead of it (#525).
    Future<void> untilMounted() async {
      final id = editor().instanceId;
      for (var i = 0; i < 5000; i++) {
        if (gateway.isSourceReady(id)) break;
        System.instance
          ..renderOffline(1)
          ..update();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(gateway.isSourceReady(id), isTrue, reason: 'joined the mix');
    }

    Future<PatchNode> create(Finder canvas, Offset scene, String line) async {
      final view = viewOf(canvas);
      final at = tester.getTopLeft(canvas) + scene;
      final patch = editorOf(canvas);
      final before = patch.nodesIn(null).map((n) => n.id).toSet();
      final field = find.descendant(
        of: canvas,
        matching: find.byKey(PatchInlineObjectBox.fieldKey),
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        await keyboard.focus(view);
        await untilWindowActive(tester);
        if (field.evaluate().isEmpty) {
          await tester.tapAt(at, view: view);
          await tester.pump();
          await tester.tapAt(at, view: view);
          await tester.pumpAndSettle();
        }
        expect(field, findsOneWidget, reason: 'inline box for "$line"');
        await keyboard.type(field, line);
        expect(keyboard.textIn(field), line);
        await keyboard.enter(
          until: () => patch.nodesIn(null).length > before.length,
        );
        if (patch.nodesIn(null).length > before.length) break;
      }
      final made = patch.nodesIn(null).where((n) => !before.contains(n.id));
      expect(made, hasLength(1), reason: '"$line" was made');
      return made.single;
    }

    Offset inletOf(PatchNodeId id) =>
        tester.getRect(nodeView(mainCanvas(), id)).topLeft +
        Offset(patchPortOffsetAlongEdge(0), 0);

    Offset outletOf(PatchNodeId id) =>
        tester.getRect(nodeView(mainCanvas(), id)).bottomLeft +
        Offset(patchPortOffsetAlongEdge(0), 0);

    Future<void> wire(Offset from, Offset to) async {
      final cables = editor().graph.cables.length;
      final pointer = await tester.startGesture(from);
      await tester.pump();
      await pointer.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await pointer.moveTo(to);
      await tester.pump();
      await pointer.up();
      await tester.pumpAndSettle();
      expect(editor().graph.cables, hasLength(cables + 1));
    }

    // Picks [item] from the node menu of [id] in the main window, which has
    // painted by now: on Linux X11 a window opened before that exits the app
    // (#556).
    Future<void> menuItem(PatchNodeId id, Key item) async {
      final g = await tester.startGesture(
        tester.getCenter(nodeView(mainCanvas(), id)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(item));
      await tester.pumpAndSettle();
    }

    Future<void> openDefinition(PatchNodeId box) async {
      await menuItem(box, PatcherSurface.openDefinitionItemKey);
      expect(find.byType(SubpatchWindowView), findsOneWidget);
      // A view the engine itself made, not a test stand-in.
      expect(PlatformDispatcher.instance.views, hasLength(2));
      // The platform sizes a new window after its first frame.
      for (var i = 0; i < 250 && windowCanvas().evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(windowCanvas(), findsOneWidget);
    }

    Iterable<String> typesIn(PatchNodeId box) =>
        editor().nodesIn(box).map((n) => n.type);

    // ── Launch 1: a chain, an abstraction, a second instance ──────────────
    final first = await launch('launch-1', newPath: dir);

    final sine = await create(mainCanvas(), const Offset(300, 80), '~sine 440');
    final gain = await create(mainCanvas(), const Offset(300, 220), '~* 0.5');
    final dac = await create(mainCanvas(), const Offset(300, 360), '~dac');
    await wire(outletOf(sine.id), inletOf(gain.id));
    await wire(outletOf(gain.id), inletOf(dac.id));

    await keyboard.focus(viewOf(mainCanvas()));
    await tester.tap(nodeView(mainCanvas(), gain.id));
    await tester.pumpAndSettle();
    await menuItem(gain.id, PatcherSurface.encapsulateItemKey);
    final boxOne = editor().graph.selectedNodes.single;
    expect(editor().isSubpatch(boxOne), isTrue);

    await menuItem(boxOne, PatcherSurface.makeAbstractionItemKey);
    final address = EntityAddress.parse('patch.abstraction');
    expect(editor().abstractionOf(boxOne), address);
    expect(engine.patchLibrary.openAddress, isNot(address), reason: 'stays');
    expect(find.text('patcher patch.abstraction'), findsOneWidget);
    expect(editor().graph.nodeById(gain.id), isNotNull, reason: 'kept');

    final sineTwo = await create(
      mainCanvas(),
      const Offset(620, 80),
      '~sine 660',
    );
    final boxTwo = await create(
      mainCanvas(),
      const Offset(620, 220),
      'patcher patch.abstraction',
    );
    expect(boxTwo.type, Obj.patcher);
    expect(editor().abstractionOf(boxTwo.id), address);
    expect(typesIn(boxTwo.id).toSet(), {
      Obj.dInlet,
      Obj.dMultiply,
      Obj.dOutlet,
    });
    final face = tester.widget<PatchObjectBox>(
      find.descendant(
        of: nodeView(mainCanvas(), boxTwo.id),
        matching: find.byType(PatchObjectBox),
      ),
    );
    expect(face.inputPortXs, hasLength(1), reason: 'the pins are the patch\'s');
    expect(face.outputPortXs, hasLength(1));
    await wire(outletOf(sineTwo.id), inletOf(boxTwo.id));
    await wire(outletOf(boxTwo.id), inletOf(dac.id));

    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('master').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    await untilMounted();
    expect(loudness(), greaterThan(0.05), reason: 'both heard');

    // ── Edit the definition, in its own window ────────────────────────────
    await openDefinition(boxOne);
    expect(
      tester.widget<Text>(find.byKey(SubpatchWindowView.titleKey)).data,
      'patch.abstraction',
    );
    final definition = editorOf(windowCanvas());
    expect(identical(definition, editor()), isFalse);
    final stage = definition
        .nodesIn(null)
        .singleWhere((n) => n.type == Obj.dMultiply);

    await keyboard.focus(viewOf(windowCanvas()));
    await tester.tap(nodeView(windowCanvas(), stage.id));
    await tester.pumpAndSettle();
    await keyboard.delete(
      until: () => definition.graph.nodeById(stage.id) == null,
    );
    expect(definition.graph.nodeById(stage.id), isNull);
    expect(typesIn(boxOne), isNot(contains(Obj.dMultiply)));
    expect(typesIn(boxTwo.id), isNot(contains(Obj.dMultiply)));
    loudness(20);
    expect(loudness(), lessThan(1e-4), reason: 'neither gets through');

    // Ctrl+Z belongs to the window it is pressed in: the definition's edit.
    await keyboard.control(
      LogicalKeyboardKey.keyZ,
      until: () => definition.graph.nodeById(stage.id) != null,
    );
    expect(definition.graph.nodeById(stage.id), isNotNull);
    expect(typesIn(boxOne), contains(Obj.dMultiply));
    expect(typesIn(boxTwo.id), contains(Obj.dMultiply));
    loudness(20);
    expect(loudness(), greaterThan(0.05), reason: 'both back after the undo');

    // Save through the File menu.
    await keyboard.focus(viewOf(mainCanvas()));
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(first.project.isDirty.value, isFalse);

    // ── Launch 2: reopen ──────────────────────────────────────────────────
    final second = await launch('launch-2');
    expect(find.byType(SubpatchWindowView), findsNothing);
    await first.engine.dispose();
    first.project.dispose();
    first.settings.dispose();
    first.session.dispose();

    final parentAddress = EntityAddress.parse('patch.patch_1');
    engine.patchLibrary.open(parentAddress);
    await tester.pumpAndSettle();
    final boxes = editor()
        .nodesIn(null)
        .where((n) => n.type == Obj.patcher)
        .toList();
    expect(boxes, hasLength(2));
    for (final box in boxes) {
      expect(editor().abstractionOf(box.id), address);
      expect(typesIn(box.id).toSet(), {Obj.dInlet, Obj.dMultiply, Obj.dOutlet});
      expect(box.inputs, hasLength(1));
      expect(box.outputs, hasLength(1));
    }
    expect(
      engine.patchLibrary.impactOf(address).referrers,
      contains(parentAddress),
      reason: 'deleting the definition would name this patch',
    );

    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    await untilMounted();
    expect(loudness(), greaterThan(0.05), reason: 'heard after reopening');

    // A definition reloaded from disk is still what they follow.
    await openDefinition(boxes.first.id);
    final reloaded = editorOf(windowCanvas());
    final again = reloaded
        .nodesIn(null)
        .singleWhere((n) => n.type == Obj.dMultiply);
    await keyboard.focus(viewOf(windowCanvas()));
    await tester.tap(nodeView(windowCanvas(), again.id));
    await tester.pumpAndSettle();
    await keyboard.delete(
      until: () => reloaded.graph.nodeById(again.id) == null,
    );
    for (final box in boxes) {
      expect(typesIn(box.id), isNot(contains(Obj.dMultiply)));
    }
    loudness(20);
    expect(loudness(), lessThan(1e-4), reason: 'followed after reopening');

    // Leaving the patch closes the definition's window.
    second.engine.patchLibrary.newPatch();
    await tester.pumpAndSettle();
    expect(find.byType(SubpatchWindowView), findsNothing);
    expect(textInput.errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(textInput.errors, isEmpty);
    await second.engine.dispose();
    second.project.dispose();
    second.settings.dispose();
    second.session.dispose();
  });
}
