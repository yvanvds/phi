import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patcher_graph_snapshot.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/patcher_surface.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
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

/// End-to-end proof of `#0` in an abstraction (issue #561), through the real
/// [PhiApp], second **native** windows and the real patcher engine
/// ([RealPatcherGateway] over an offline libyse session). Only the audio device,
/// MIDI and the project store are fakes.
///
/// The performer types a definition whose message box sends through
/// `.s ping#0` to a `.r ping#0` and a number box, and makes two instances. The
/// reference panel says each one's number. Clicking the message box in one
/// instance's own window fills that instance's number box and not the other's:
/// mounted and rendered, so this is the patcher's own in-patcher path, not only
/// the bus. A duplicate gets a number of its own. Saved and reopened, the numbers
/// and names are what they were; an edit in the definition's window does not
/// touch them, and the instances are still apart.
void main() {
  NativeWindowsTestBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: #0 keeps two instances\' names apart, through a save '
      'and an edit of their definition', (tester) async {
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

    const dir = '/projects/instance_number.phi';
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

    Finder canvasOf(PatcherController patch) => find.byWidgetPredicate(
      (w) => w is PatcherCanvas && identical(w.controller, patch),
    );

    Finder mainCanvas() => find.byWidgetPredicate(
      (w) =>
          w is PatcherCanvas &&
          identical(w.controller, editor()) &&
          w.scope == null,
    );

    Finder instanceWindowCanvas(PatchNodeId box) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is SubpatchWindowView && w.box == box,
      ),
      matching: find.byKey(SubpatchWindowView.canvasKey),
    );

    Finder nodeView(Finder canvas, PatchNodeId id) => find.descendant(
      of: canvas,
      matching: find.byWidgetPredicate(
        (w) => w is PatcherNodeView && w.node.id == id,
      ),
    );

    FlutterView viewOf(Finder f) => tester.viewOf(f);

    void render([int blocks = 50]) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
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

    Future<PatchNode> create(
      Finder canvas,
      PatcherController patch,
      Offset scene,
      String line,
    ) async {
      final view = viewOf(canvas);
      final at = tester.getTopLeft(canvas) + scene;
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

    // The platform sizes a new window after its first frame.
    Future<void> untilShown(Finder canvas) async {
      for (var i = 0; i < 250 && canvas.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(canvas, findsOneWidget);
    }

    Future<void> startOnMaster() async {
      await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
      await tester.pumpAndSettle();
      await untilMounted();
    }

    PatchNode inBox(PatchNodeId box, String type) =>
        editor().nodesIn(box).singleWhere((n) => n.type == type);

    /// The native `.s` holding this instance's name: its handle says whether an
    /// edit replaced it, and its container is the instance's box.
    PatcherObjectSnapshot nativeSend(PatchNodeId box) {
      final name = 'ping#${editor().instanceNumberOf(box)} 0';
      return gateway
          .enumerate(editor().instanceId)
          .objects
          .singleWhere((o) => o.type == Obj.gSend && o.args == name);
    }

    /// What the `.f` inside [box] shows, read from the native object.
    double shown(PatchNodeId box) {
      final instance = editor().instanceId;
      final readout = gateway
          .enumerate(instance)
          .objects
          .singleWhere(
            (o) =>
                o.type == Obj.gFloat &&
                o.container == nativeSend(box).container,
          );
      return double.tryParse(gateway.guiValue(instance, readout.handleId)) ?? 0;
    }

    /// Opens [box]'s own window and clicks the message box in it.
    Future<void> playInWindow(PatchNodeId box) async {
      await menuItem(box, PatcherSurface.openSubpatchItemKey);
      final canvas = instanceWindowCanvas(box);
      await untilShown(canvas);
      expect(
        tester.widget<PatcherCanvas>(canvas).mode,
        PatchCanvasMode.run,
        reason: 'an instance\'s window is played',
      );
      await keyboard.focus(viewOf(canvas));
      await untilWindowActive(tester);
      final number = editor().instanceNumberOf(box);
      expect(
        find.descendant(of: canvas, matching: find.text('s ping#$number 0')),
        findsOneWidget,
        reason: 'the window shows the name this instance really uses',
      );
      await tester.tap(nodeView(canvas, inBox(box, Obj.gMessage).id));
      await tester.pumpAndSettle();
      render();
      await tester.pumpAndSettle();
    }

    Future<String> numberInPanel(PatchNodeId box) async {
      await keyboard.focus(viewOf(mainCanvas()));
      await tester.tap(nodeView(mainCanvas(), box));
      await tester.pumpAndSettle();
      return tester
          .widget<Text>(find.byKey(PatchReferencePanel.subpatchInstanceKey))
          .data!;
    }

    // ── Launch 1: a definition using #0, two instances of it ──────────────
    final first = await launch('launch-1', newPath: dir);
    final parentAddress = engine.patchLibrary.openAddress!;

    final address = engine.patchLibrary.newPatch()!;
    await tester.pumpAndSettle();
    final message = await create(
      mainCanvas(),
      editor(),
      const Offset(300, 80),
      '.m 5',
    );
    final send = await create(
      mainCanvas(),
      editor(),
      const Offset(300, 220),
      '.s ping#0',
    );
    final receive = await create(
      mainCanvas(),
      editor(),
      const Offset(620, 80),
      '.r ping#0',
    );
    final readout = await create(
      mainCanvas(),
      editor(),
      const Offset(620, 220),
      '.f',
    );
    await wire(outletOf(message.id), inletOf(send.id));
    await wire(outletOf(receive.id), inletOf(readout.id));
    expect(
      find.text('s ping#0 0'),
      findsOneWidget,
      reason: 'a definition shows its token as typed',
    );

    engine.patchLibrary.open(parentAddress);
    await tester.pumpAndSettle();
    final one = await create(
      mainCanvas(),
      editor(),
      const Offset(300, 80),
      'patcher ${address.format()}',
    );
    final two = await create(
      mainCanvas(),
      editor(),
      const Offset(620, 80),
      'patcher ${address.format()}',
    );
    final sine = await create(
      mainCanvas(),
      editor(),
      const Offset(300, 240),
      '~sine 440',
    );
    final dac = await create(
      mainCanvas(),
      editor(),
      const Offset(300, 380),
      '~dac',
    );
    await wire(outletOf(sine.id), inletOf(dac.id));

    final numberOne = editor().instanceNumberOf(one.id)!;
    final numberTwo = editor().instanceNumberOf(two.id)!;
    expect(numberOne, isNot(numberTwo));
    expect(await numberInPanel(one.id), '= #$numberOne');
    expect(await numberInPanel(two.id), '= #$numberTwo');
    expect(editor().argsOf(inBox(one.id, Obj.gSend).id), 'ping#$numberOne 0');
    expect(
      editor().argsOf(inBox(two.id, Obj.gReceive).id),
      'ping#$numberTwo 0',
    );

    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('master').last);
    await tester.pumpAndSettle();
    await startOnMaster();

    // ── Play one instance: the other does not hear it ─────────────────────
    expect(shown(one.id), 0);
    await playInWindow(one.id);
    expect(shown(one.id), 5, reason: 'its own .r heard its own .s');
    expect(shown(two.id), 0, reason: 'the other instance heard nothing');

    // ── A duplicate gets its own number and the first one stays ───────────
    await keyboard.focus(viewOf(mainCanvas()));
    await tester.tap(nodeView(mainCanvas(), two.id));
    await tester.pumpAndSettle();
    final patcherBoxes = editor().nodesIn(null).length;
    await keyboard.control(
      LogicalKeyboardKey.keyD,
      until: () => editor().nodesIn(null).length > patcherBoxes,
    );
    await tester.pumpAndSettle();
    final boxes = editor()
        .nodesIn(null)
        .where((n) => n.type == Obj.patcher)
        .map((n) => n.id)
        .toList();
    expect(boxes, hasLength(3));
    final numbers = {
      for (final box in boxes) box: editor().instanceNumberOf(box)!,
    };
    expect(numbers.values.toSet(), hasLength(3));
    expect(numbers[one.id], numberOne);
    expect(numbers[two.id], numberTwo);

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

    // ── Launch 2: reopen. The numbers, and every name, are where they were ─
    final second = await launch('launch-2');
    expect(find.byType(SubpatchWindowView), findsNothing);
    await first.engine.dispose();
    first.project.dispose();
    first.settings.dispose();
    first.session.dispose();

    engine.patchLibrary.open(parentAddress);
    await tester.pumpAndSettle();
    final reopened = editor()
        .nodesIn(null)
        .where((n) => n.type == Obj.patcher)
        .toList();
    expect(
      reopened.map((n) => editor().instanceNumberOf(n.id)).toSet(),
      numbers.values.toSet(),
      reason: 'the numbers were saved',
    );
    for (final box in reopened) {
      final number = editor().instanceNumberOf(box.id);
      expect(editor().argsOf(inBox(box.id, Obj.gSend).id), 'ping#$number 0');
      expect(editor().argsOf(inBox(box.id, Obj.gReceive).id), 'ping#$number 0');
    }

    // An edit in the definition's own window leaves the names, and the native
    // objects holding them, alone.
    final target = reopened.first;
    final sendHandle = nativeSend(target.id).handleId;
    final cablesBefore = gateway
        .enumerate(editor().instanceId)
        .connections
        .length;
    await menuItem(target.id, PatcherSurface.openDefinitionItemKey);
    final definition = engine.patchLibrary.editorFor(address)!;
    final definitionCanvas = canvasOf(definition);
    await untilShown(definitionCanvas);
    await create(definitionCanvas, definition, const Offset(300, 360), '.b');
    expect(
      editor().nodesIn(target.id).where((n) => n.type == Obj.gButton),
      hasLength(1),
      reason: 'the instance followed',
    );
    expect(
      nativeSend(target.id).handleId,
      sendHandle,
      reason: 'the name\'s object was not touched',
    );
    expect(
      editor().argsOf(inBox(target.id, Obj.gSend).id),
      'ping#${editor().instanceNumberOf(target.id)} 0',
    );
    expect(
      gateway.enumerate(editor().instanceId).connections,
      hasLength(cablesBefore),
      reason: 'no cable moved',
    );

    // Still apart, after all that.
    final other = reopened.last;
    await startOnMaster();
    await playInWindow(other.id);
    expect(shown(other.id), 5);
    expect(shown(target.id), 0);

    // Leaving the patch closes both windows.
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
