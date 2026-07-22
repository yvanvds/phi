import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/state_slice_category.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/state/state_entity_selection.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/engine/state/state_slice_source.dart';
import 'package:phi/shell/right_inspector/right_inspector.dart';
import 'package:phi/shell/right_inspector/state_inspector_panel.dart';
import 'package:phi/surfaces/state/state_canvas.dart';
import 'package:phi/surfaces/state/state_transition_badge.dart';
import 'package:phi/surfaces/state/state_trigger_editor.dart';

/// A controllable [StateSliceSource]: each capture returns a copy of the
/// configured value, so tests shape the "live performance" directly.
class _FakeSliceSource implements StateSliceSource {
  List<ClipSliceEntry> clips = [];
  List<MixSliceEntry> mix = [];
  Map<String, String> variables = {};
  List<TempoSliceEntry> tempos = [];

  @override
  List<ClipSliceEntry> captureClips() => List.of(clips);

  @override
  List<MixSliceEntry> captureMix() => List.of(mix);

  @override
  Map<String, String> captureVariables() => Map.of(variables);

  @override
  List<TempoSliceEntry> captureTempos() => List.of(tempos);
}

/// The inspector half of issue #245: SLICES / ON ENTER / TRANSITIONS panels
/// mutating the payload through the controller's journaled commands, the
/// not-captured vs captured-empty distinction, and canvas ↔ inspector
/// consistency after edits from either side.
void main() {
  late StateMachineController controller;
  late SessionState session;
  late RuntimeVariableRegistry variables;
  late List<ProjectCommand> recorded;
  late _FakeSliceSource source;
  late EntityAddress intro;
  late EntityAddress verse;
  late EntityAddress bridge;

  final drum = EntityAddress.parse('domain.drum');
  final phraseA = EntityAddress.parse('clip.phrase_a');
  final pads = EntityAddress.parse('mix.pads');
  final scratch = EntityAddress.parse('code.scratch');

  setUp(() {
    recorded = [];
    controller = StateMachineController(recordCommand: recorded.add);
    session = SessionState();
    variables = RuntimeVariableRegistry()
      ..define(name: 'section', values: ['a', 'b'], current: 'a');
    source = _FakeSliceSource();
    intro = controller.addState(
      name: 'intro',
      position: const Offset(160, 160),
    );
    verse = controller.addState(
      name: 'verse',
      position: const Offset(400, 160),
    );
    bridge = controller.addState(
      name: 'bridge',
      position: const Offset(160, 400),
    );
    controller.connect(intro, verse);
    controller.sliceSource = source;
    controller.registry.createEntity(
      EntityAddress(kind: RegistryKinds.domain, segments: const ['drum']),
      payload: const TimeDomain(name: 'drum', tempo: 124),
    );
    controller.registry.createEntity(
      EntityAddress(kind: RegistryKinds.code, segments: const ['scratch']),
      payload: const {'source': ''},
    );
    recorded.clear();
  });

  tearDown(() {
    controller.dispose();
    session.dispose();
  });

  StateDocument docOf(EntityAddress address) => controller.documentOf(address)!;

  StateEntitySelection selectionOf(EntityAddress address) =>
      StateEntitySelection(
        controller: controller,
        address: address,
        variables: variables,
      );

  /// Pump the bare panel at the inspector's width on a tall surface, so
  /// every section is on-screen without scrolling.
  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: StateInspectorPanel(
                  selection: selectionOf(intro),
                  session: session,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('SLICES', () {
    testWidgets('uncaptured categories read not captured', (tester) async {
      await pumpPanel(tester);

      expect(find.text('not captured'), findsNWidgets(4));
      expect(find.text('captured · empty'), findsNothing);
      // Nothing captured → no clear action anywhere.
      expect(find.text('clear'), findsNothing);
    });

    testWidgets('capture is inert without a slice source', (tester) async {
      controller.sliceSource = null;
      await pumpPanel(tester);

      await tester.tap(
        find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.clips)),
      );
      await tester.pump();

      expect(recorded, isEmpty);
      expect(find.text('not captured'), findsNWidgets(4));
    });

    testWidgets('capture lists the live entries per category through '
        'journaled commands', (tester) async {
      source
        ..clips = [ClipSliceEntry(clip: phraseA)]
        ..mix = [MixSliceEntry(bus: pads, volume: 0.4, muted: true)]
        ..variables = {'section': 'a'}
        ..tempos = [TempoSliceEntry(domain: drum, bpm: 124)];
      await pumpPanel(tester);

      for (final category in StateSliceCategory.values) {
        await tester.tap(find.byKey(StateInspectorPanel.captureKey(category)));
        await tester.pump();
      }

      expect(recorded, hasLength(4));
      expect(find.text('phrase_a · loop'), findsOneWidget);
      expect(find.text('pads · 0.40 · muted'), findsOneWidget);
      expect(find.text('section = a'), findsOneWidget);
      expect(find.text('drum · 124 bpm'), findsOneWidget);
      expect(find.text('not captured'), findsNothing);
      expect(find.text('clear'), findsNWidgets(4));

      final slices = docOf(intro).slices;
      expect(slices.clips, [ClipSliceEntry(clip: phraseA)]);
      expect(slices.mix, [MixSliceEntry(bus: pads, volume: 0.4, muted: true)]);
      expect(slices.variables, {'section': 'a'});
      expect(slices.tempos, [TempoSliceEntry(domain: drum, bpm: 124)]);
    });

    testWidgets('a live-empty capture reads captured · empty — distinct '
        'from not captured', (tester) async {
      await pumpPanel(tester);

      await tester.tap(
        find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.clips)),
      );
      await tester.pump();

      expect(find.text('captured · empty'), findsOneWidget);
      expect(find.text('not captured'), findsNWidgets(3));
      expect(docOf(intro).slices.clips, isEmpty);
    });

    testWidgets('per-entry remove trims the capture; removing the last '
        'entry keeps captured-but-empty', (tester) async {
      source
        ..clips = [ClipSliceEntry(clip: phraseA)]
        ..variables = {'section': 'a', 'mode': 'lead'};
      await pumpPanel(tester);
      await tester.tap(
        find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.clips)),
      );
      await tester.tap(
        find.byKey(
          StateInspectorPanel.captureKey(StateSliceCategory.variables),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(StateInspectorPanel.removeVariableEntryKey('mode')),
      );
      await tester.pump();
      expect(find.text('mode = lead'), findsNothing);
      expect(find.text('section = a'), findsOneWidget);
      expect(docOf(intro).slices.variables, {'section': 'a'});

      await tester.tap(
        find.byKey(StateInspectorPanel.removeClipEntryKey(phraseA)),
      );
      await tester.pump();
      expect(find.text('phrase_a · loop'), findsNothing);
      expect(find.text('captured · empty'), findsOneWidget);
      expect(docOf(intro).slices.clips, isEmpty);
    });

    testWidgets('clear returns a category to uncaptured', (tester) async {
      source.clips = [ClipSliceEntry(clip: phraseA)];
      await pumpPanel(tester);
      await tester.tap(
        find.byKey(StateInspectorPanel.captureKey(StateSliceCategory.clips)),
      );
      await tester.pump();
      expect(find.text('not captured'), findsNWidgets(3));

      await tester.tap(
        find.byKey(StateInspectorPanel.clearKey(StateSliceCategory.clips)),
      );
      await tester.pump();

      expect(find.text('not captured'), findsNWidgets(4));
      expect(docOf(intro).slices.clips, isNull);
      expect(
        find.byKey(StateInspectorPanel.clearKey(StateSliceCategory.clips)),
        findsNothing,
      );
    });
  });

  group('ON ENTER', () {
    testWidgets('the picker offers the code tree and sets the script', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.tap(find.byKey(StateInspectorPanel.onEnterKey));
      await tester.pumpAndSettle();
      expect(find.text('none'), findsNWidgets(2)); // closed control + option
      await tester.tap(find.text('code.scratch').last);
      await tester.pumpAndSettle();

      expect(docOf(intro).onEnter, scratch);
      expect(recorded, hasLength(1));
      expect(find.text('code.scratch'), findsOneWidget);

      await tester.tap(find.byKey(StateInspectorPanel.onEnterKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('none').last);
      await tester.pumpAndSettle();
      expect(docOf(intro).onEnter, isNull);
    });

    testWidgets('a stored script no longer in the project stays offered '
        'as missing', (tester) async {
      controller.setOnEnter(intro, EntityAddress.parse('code.ghost'));
      await pumpPanel(tester);

      expect(find.text('code.ghost · missing'), findsOneWidget);
    });
  });

  group('TRANSITIONS', () {
    testWidgets('the outbound list shows target, trigger and label; the '
        'summary opens the editor and saves through the controller', (
      tester,
    ) async {
      await pumpPanel(tester);

      expect(find.text('→ verse'), findsOneWidget);
      expect(find.text('manual'), findsOneWidget);
      expect(find.text('label…'), findsOneWidget);

      await tester.tap(
        find.byKey(StateInspectorPanel.transitionTriggerKey(verse)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StateTriggerEditor), findsOneWidget);

      await tester.tap(find.byKey(StateTriggerEditor.kindKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('timed').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(StateTriggerEditor.beatsKey), '16');
      await tester.tap(find.byKey(StateTriggerEditor.saveKey));
      await tester.pumpAndSettle();

      expect(
        controller.triggerOf(intro, verse),
        TimedTrigger(beats: 16, domain: drum),
      );
      expect(find.text('timed · 16 beats on drum'), findsOneWidget);
    });

    testWidgets('the editor offers the selection runtime variables', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.tap(
        find.byKey(StateInspectorPanel.transitionTriggerKey(verse)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StateTriggerEditor.kindKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('variable').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StateTriggerEditor.valueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StateTriggerEditor.saveKey));
      await tester.pumpAndSettle();

      expect(
        controller.triggerOf(intro, verse),
        const VariableTrigger(name: 'section', value: 'b'),
      );
      expect(find.text('variable · section = b'), findsOneWidget);
    });

    testWidgets('the label inline-edits through the journaled '
        'setTransitionLabel', (tester) async {
      await pumpPanel(tester);

      await tester.tap(
        find.byKey(StateInspectorPanel.transitionLabelKey(verse)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'drop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(docOf(intro).transitions.single.label, 'drop');
      expect(recorded, hasLength(1));
      expect(find.text('drop'), findsOneWidget);
      expect(find.text('label…'), findsNothing);

      // Clearing the text clears the label back to unset.
      await tester.tap(
        find.byKey(StateInspectorPanel.transitionLabelKey(verse)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(docOf(intro).transitions.single.label, isNull);
      expect(find.text('label…'), findsOneWidget);
    });

    testWidgets('add offers only unconnected non-self targets; remove '
        'drops the transition', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.byKey(StateInspectorPanel.addTransitionKey));
      await tester.pumpAndSettle();
      // `intro` (self) and `verse` (already targeted) are not offered.
      expect(find.text('bridge'), findsOneWidget);
      expect(find.text('verse'), findsNothing);
      await tester.tap(find.text('bridge'));
      await tester.pumpAndSettle();

      expect(find.text('→ bridge'), findsOneWidget);
      expect(docOf(intro).transitions.map((s) => s.to), [verse, bridge]);

      await tester.tap(
        find.byKey(StateInspectorPanel.removeTransitionKey(verse)),
      );
      await tester.pump();
      expect(find.text('→ verse'), findsNothing);
      expect(docOf(intro).transitions.single.to, bridge);

      await tester.tap(
        find.byKey(StateInspectorPanel.removeTransitionKey(bridge)),
      );
      await tester.pump();
      expect(find.text('—'), findsOneWidget);
      expect(docOf(intro).transitions, isEmpty);
    });
  });

  group('canvas ↔ inspector', () {
    Finder onCanvas(String text) => find.descendant(
      of: find.byType(StateCanvas),
      matching: find.text(text),
    );

    testWidgets('stay consistent after edits from either side', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: StateCanvas(
                    controller: controller,
                    session: session,
                    variables: variables,
                  ),
                ),
                RightInspector(session: session),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Select `intro` on the canvas and expand the inspector.
      await tester.tap(onCanvas('intro'));
      await tester.pump();
      await tester.tap(find.text('INSPECTOR'));
      await tester.pumpAndSettle();
      expect(find.text('state.intro'), findsOneWidget);
      expect(find.text('manual'), findsOneWidget);

      // Canvas-side edit: tap the intro → verse curve, save a timed trigger
      // — the inspector row reflects it.
      final origin = tester.getTopLeft(find.byType(StateCanvas));
      await tester.tapAt(origin + const Offset(292, 188));
      await tester.pumpAndSettle();
      expect(find.byType(StateTriggerEditor), findsOneWidget);
      await tester.tap(find.byKey(StateTriggerEditor.kindKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('timed').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StateTriggerEditor.saveKey));
      await tester.pumpAndSettle();
      expect(find.text('timed · 4 beats on drum'), findsOneWidget);
      expect(find.text('TIMED'), findsOneWidget);

      // Inspector-side edit: remove the transition — the canvas badge goes.
      await tester.tap(
        find.byKey(StateInspectorPanel.removeTransitionKey(verse)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StateTransitionBadge), findsNothing);
      expect(find.text('—'), findsOneWidget);

      // Inspector-side add: connect intro → verse again — the canvas
      // renders the fresh manual badge.
      await tester.tap(find.byKey(StateInspectorPanel.addTransitionKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('verse').last);
      await tester.pumpAndSettle();
      expect(find.text('MANUAL'), findsOneWidget);
      expect(docOf(intro).transitions.single.to, verse);
    });
  });
}
