import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_dial_knob.dart';
import 'package:phi/design/widgets/patcher/patch_incdec_stepper.dart';
import 'package:phi/design/widgets/patcher/patch_led_lamp.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_text_button.dart';
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

/// End-to-end proof of the **single-value control tutorials** (issue #491)
/// through the real [PhiApp]: real rail navigation, fonts and layout, the real asset
/// bundle and the real patcher engine ([RealPatcherGateway] on an offline
/// libyse session). Only the audio device and MIDI are fakes.
///
/// Each of `.dial`, `.incdec`, `.led`, `.textbutton`, `.textedit` and `.l` is
/// opened from the palette's Tutorials tab. The test checks that its notes render,
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

  testWidgets('patcher: every single-value control tutorial opens from the '
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
          newLocationPath: '/projects/single-value-controls.phi',
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

    // The message boxes spelling [text], top to bottom on the canvas.
    List<Finder> messages(String text) {
      final all =
          [
            for (var i = 0; i < message(text).evaluate().length; i++)
              message(text).at(i),
          ]..sort(
            (a, b) =>
                tester.getTopLeft(a).dy.compareTo(tester.getTopLeft(b).dy),
          );
      return all;
    }

    // The highest of the widgets [f] finds on the canvas.
    Finder topmost(Finder f) {
      final all = [for (var i = 0; i < f.evaluate().length; i++) f.at(i)]
        ..sort(
          (a, b) => tester.getTopLeft(a).dy.compareTo(tester.getTopLeft(b).dy),
        );
      return all.first;
    }

    Finder lamp(String label) =>
        find.byWidgetPredicate((w) => w is PatchLedLamp && w.label == label);
    Finder button(String label) =>
        find.byWidgetPredicate((w) => w is PatchTextButton && w.label == label);

    // ── .dial: exponent 1 against 3, and intMode ────────────────────────────
    var at = await open(
      '.dial',
      slug: 'dial',
      notes: 6,
      heading: 'A dial holds a position from 0 to 1',
    );
    await tap(message('0.5'));
    expect(double.parse(value(at('.f', 60, 290))), 500.0);
    expect(double.parse(value(at('.f', 170, 290))), 125.0);
    expect(
      [
        for (final e in find.byType(PatchDialKnob).evaluate())
          (e.widget as PatchDialKnob).position,
      ].where((p) => p == 0.5),
      hasLength(2),
      reason: 'both knobs point to the middle',
    );
    await tap(message('0.75'));
    expect(value(at('.i', 60, 550)), '8');
    expect(double.parse(value(at('.f', 170, 550))), 7.5);
    await close();

    // ── .incdec: the stepper's own halves, a silent set, wrap ───────────────
    at = await open(
      '.incdec',
      slug: 'incdec',
      notes: 6,
      heading: 'An incdec holds a whole number',
    );
    // The highest stepper on the canvas is incdec 1 0 20; press its top half.
    final steppers = [
      for (final e in find.byType(PatchIncdecStepper).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ]..sort((a, b) => a.top.compareTo(b.top));
    expect(steppers, hasLength(3));
    final first = steppers.first;
    await tester.tapAt(first.center - Offset(0, first.height / 4));
    await tester.pumpAndSettle();
    expect(value(at('.i', 60, 340)), '1', reason: 'top half sends inc');
    await tap(message('3'));
    expect(value(at('.i', 60, 340)), '4', reason: 'the middle inlet nudges');
    await tap(message('7'));
    expect(value(at('.incdec', 60, 270)), '7');
    expect(value(at('.i', 60, 340)), '4', reason: 'a number sets silently');
    await tap(find.byType(PatchBangSquare));
    expect(value(at('.i', 60, 340)), '7', reason: 'a bang sends');
    final wrapInc = messages('inc').last;
    for (var i = 0; i < 4; i++) {
      await tap(wrapInc);
    }
    expect(value(at('.i', 60, 580)), '3', reason: 'clamped');
    expect(value(at('.i', 200, 580)), '0', reason: 'wrapped');
    await close();

    // ── .led: latch, momentary press, labels into one textedit ──────────────
    at = await open(
      '.led',
      slug: 'led',
      notes: 6,
      heading: 'A led is a lamp that is on',
    );
    await tap(lamp('lamp'));
    expect(value(at('.i', 60, 270)), '1');
    await tap(topmost(find.byType(PatchBangSquare)));
    expect(value(at('.i', 60, 270)), '0', reason: 'a bang flips it');
    await tap(lamp('press'));
    expect(value(at('.i', 60, 590)), '1', reason: 'a press counted');
    await tap(lamp('green'));
    expect(value(at('.textedit', 60, 750)), 'green');
    expect(
      find.descendant(
        of: find.byType(PatchTextEditBox),
        matching: find.text('green'),
      ),
      findsOneWidget,
      reason: 'the field shows the label',
    );
    await close();

    // ── .textbutton: latching mute, a bank through route ────────────────────
    at = await open(
      '.textbutton',
      slug: 'textbutton',
      notes: 5,
      heading: 'A textbutton is a led drawn as a button',
    );
    await tap(button('mute'));
    expect(value(at('.i', 60, 270)), '1');
    await tap(button('medium'));
    expect(value(at('.i', 60, 580)), '250');
    await tap(button('fast'));
    expect(value(at('.i', 60, 580)), '125');
    await close();

    // ── .textedit: type, sprintf, resend, clear ─────────────────────────────
    at = await open(
      '.textedit',
      slug: 'textedit',
      notes: 5,
      heading: 'A textedit holds a line of text',
    );
    final field = find.descendant(
      of: find.byType(PatchTextEditBox),
      matching: find.byType(EditableText),
    );
    await tap(field);
    await tester.enterText(field, 'Bob');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value(at('.textedit', 60, 210)), 'Bob', reason: 'committed');
    expect(value(at('.l', 60, 350)), 'hello Bob');
    expect(find.text('hello Bob'), findsOneWidget, reason: 'list box shows it');
    expect(value(at('.i', 230, 470)), '1');
    await tap(find.byType(PatchBangSquare));
    expect(value(at('.i', 230, 470)), '2', reason: 'a bang resends');
    final empty = topmost(find.byType(PatchListBox));
    await tap(empty);
    expect(value(at('.textedit', 60, 210)), '', reason: 'cleared');
    await close();

    // ── .l: collect silently, send on demand ────────────────────────────────
    at = await open(
      '.l',
      slug: 'l',
      notes: 5,
      heading: 'A list box holds a list',
    );
    await tap(message('7'));
    await tap(message('60'));
    expect(
      find.descendant(
        of: find.byType(PatchListBox),
        matching: find.text('60 7'),
      ),
      findsOneWidget,
      reason: 'the list box shows what it caught',
    );
    expect(value(at('.i', 60, 420)), '0', reason: 'and sends nothing');
    await tap(find.byType(PatchListBox));
    expect(value(at('.i', 60, 420)), '60');
    expect(value(at('.i', 170, 420)), '7');
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
