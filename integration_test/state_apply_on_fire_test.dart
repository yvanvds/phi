import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/code/code_script_seed.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/slices/state_slice_category.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/state_transition.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/midi/clip_transport_row.dart';
import 'package:phi/surfaces/state/state_canvas.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_code_evaluator.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the journal-free application engine (issue #243)
/// through the real [PhiApp]: capture the live performance onto `state.verse`,
/// move the performance away, save, then fire `intro → verse` from the State
/// canvas — the variables, domain tempo, mix levels and playing clips snap
/// back to the captured values in one entry, the on-enter script runs through
/// the shared evaluator, and *nothing journals*: the project stays saved and
/// the authored payloads keep the authored values. A second fire after
/// deleting a captured bus degrades gracefully with a notice.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder onCanvas(String text) =>
      find.descendant(of: find.byType(StateCanvas), matching: find.text(text));

  StateDocument stateDoc(ProjectController controller, EntityAddress address) {
    final payload = controller.registry.entityAt(address)!.payload!;
    return payload is StateDocument
        ? payload
        : StateDocument.fromJson((payload as Map).cast());
  }

  testWidgets('firing a transition applies the captured slices in order, '
      'runs the on-enter script, journals nothing, and degrades gracefully '
      'on a deleted referent', (tester) async {
    const dir = '/projects/state-apply.phi';
    final padsAddress = EntityAddress.parse('mix.pads');
    final drumDomain = EntityAddress.parse('domain.drum');
    final scratchScript = EntityAddress.parse('code.scratch');
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    final midiGateway = FakeMidiGateway();
    final evaluator = FakeCodeEvaluator();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(settings);
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(newLocationPath: dir),
        codeEvaluator: evaluator,
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // --- Shape the live performance and capture it onto `verse` -------------
    final pads = engine.addChannel(name: 'pads');
    engine.setChannelVolume(pads, 0.4);
    engine.setChannelMuted(pads, muted: true);
    engine.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );
    await tester.pumpAndSettle();

    // Start the seeded clip from the MIDI transport row so the clips capture
    // sees what actually sounds.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.midi.isPlaying, isTrue);

    final sm = engine.stateMachine;
    for (final category in StateSliceCategory.values) {
      expect(sm.captureSlice(verseStateAddress, category), isTrue);
    }

    // Shape the capture where live == authored would hide the application:
    // the captured drum tempo (authored 124) becomes 100 so the clock apply
    // is observable, and the on-enter script points at the seeded scratch.
    final verseDoc = stateDoc(controller, verseStateAddress);
    controller.registry.updateEntityPayload(
      verseStateAddress,
      verseDoc.copyWith(
        slices: verseDoc.slices.copyWith(
          tempos: [TempoSliceEntry(domain: drumDomain, bpm: 100)],
        ),
        onEnter: scratchScript,
      ),
    );

    // --- Move the performance away from the capture -------------------------
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.midi.isPlaying, isFalse);
    engine.setChannelVolume(pads, 0.9);
    engine.setChannelMuted(pads, muted: false);
    engine.runtimeVariables.setValue('section', 'b');
    await tester.pumpAndSettle();

    // Save: everything from here on is performance and must not dirty.
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.isSaved, isTrue);
    final authoredPads = controller.registry.entityAt(padsAddress)!.payload;

    // --- Fire intro → verse from the State canvas ---------------------------
    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();
    sm.toggleArmed(
      StateTransition(source: introStateAddress, target: verseStateAddress),
    );
    await tester.pump();
    expect(find.text('▲ ARMED · MANUAL'), findsOneWidget);

    await tester.tap(onCanvas('verse'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(sm.activeStateAddress, verseStateAddress);

    // Variables snapped back — the MIDI-graph context follows the state.
    expect(engine.runtimeVariables.byName('section')!.current, 'a');

    // The tempo applied through the clock binding: a live override, and the
    // drum-subscribed session's clock re-paced — while the authored domain
    // payload keeps its 124.
    expect(engine.midi.domainTempoOverride('drum'), 100);
    expect(engine.midi.editedSession.effectiveTempo, 100);

    // Mix levels applied live (the fader and mute follow)…
    final livePads = engine.channels.value.singleWhere((c) => c.name == 'pads');
    expect(livePads.volume, 0.4);
    expect(livePads.muted, isTrue);

    // …the stopped clip plays again…
    expect(engine.midi.isPlaying, isTrue);

    // …and the on-enter script ran through the shared evaluator.
    expect(evaluator.calls, [codeScratchSource]);

    // Journal-free (§8 decision 2): the application authored nothing — the
    // project is still saved and the authored payloads keep their values.
    expect(controller.isSaved, isTrue);
    expect(controller.registry.entityAt(padsAddress)!.payload, authoredPads);
    expect(engine.lastStateNotice.value, isNull);

    // --- Graceful degradation: a deleted captured referent ------------------
    // The clip keeps playing (avoid pumpAndSettle while it animates); deleting
    // the captured bus leaves the verse slice pointing at a dead address.
    engine.removeChannel(
      engine.channels.value.singleWhere((c) => c.name == 'pads'),
    );
    await tester.pump();

    sm.toggleArmed(
      StateTransition(source: introStateAddress, target: verseStateAddress),
    );
    await tester.pump();
    await tester.tap(onCanvas('verse'));
    await tester.pump(const Duration(milliseconds: 50));

    // The rest of the state still applied…
    expect(engine.midi.isPlaying, isTrue);
    expect(evaluator.calls, hasLength(2));
    // …and the dropped bus was surfaced as a notice on the entered state.
    final notice = engine.lastStateNotice.value;
    expect(notice, isNotNull);
    expect(notice!.state, verseStateAddress);
    expect(notice.message, contains('mix.pads'));

    // Wind down: stop the sessions before tearing the app down.
    engine.midi.stopAll();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
