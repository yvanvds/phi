import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/slices/state_slice_category.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/bridge/clip_control_port.dart';
import 'package:phi/engine/bridge/control_plane_dispatcher.dart';
import 'package:phi/engine/bridge/tempo_control_port.dart';
import 'package:phi/engine/bridge/variable_control_port.dart';
import 'package:phi/engine/bridge/voice_control_port.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/state_machine_control_port.dart';
import 'package:phi/engine/state/state_trigger_scheduler.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_bus_tap.dart';
import '../test/engine/test_doubles/fake_code_evaluator.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// The state-graph epic's end-to-end walk (issue #246): a two-state
/// performance through the real [PhiApp], with every cross-epic seam faked —
/// the engine bus tap (the C API is a pending engine dependency), the script
/// evaluator, and the control plane's clip/voice/var/tempo controllers.
///
/// The walk: shape the intro performance and **capture** its mix + variable
/// slices onto `verse`; author the graph (a timed `verse → intro` follow-on)
/// and a MIDI-graph branch guarded on `state.verse`; move the performance
/// away and save. Then **fire to `verse` from live code**: the exact frame
/// `state.verse.fire()` publishes (proven byte-for-byte by the `phi` library's
/// Python suite) rides the fake tap into the real [ControlPlaneDispatcher],
/// through the real [StateMachineControlPort], and out the scheduler's normal
/// fire path — the slices apply, the journal stays empty, `state.current`
/// reaches the shared evaluator, the guarded branch re-routes the preview
/// exactly as a manual fire would, and the timed follow-on starts counting on
/// its reserved domain-paced clock. An early manual exit cancels the count;
/// re-triggering `intro → verse` as a **variable-match** transition then
/// re-routes the guarded branch again the moment the variable moves.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('a two-state performance: capture, fire-from-code through the '
      'control plane, timed follow-on cancelled on early exit, and a '
      'variable-match fire re-routing a guarded MIDI branch', (tester) async {
    const dir = '/projects/state-end-to-end.phi';
    final padsAddress = EntityAddress.parse('mix.pads');
    final drumDomain = EntityAddress.parse('domain.drum');
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();

    final midiGateway = FakeMidiGateway();
    final evaluator = FakeCodeEvaluator();
    final busTap = FakeBusTap();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      busTap: busTap,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
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

    // The control plane over the engine's tap: the *real* dispatcher and the
    // *real* state port; the other owning controllers stay faked — the
    // cross-epic seams (#233's fakes) this walk is explicitly allowed to keep.
    final notices = <String>[];
    final inert = _InertPorts();
    final dispatcher = ControlPlaneDispatcher(
      busTap: busTap,
      clips: inert,
      voices: inert,
      variables: inert,
      states: StateMachineControlPort(engine.stateTriggers),
      tempo: inert,
      onNotice: notices.add,
    );
    addTearDown(dispatcher.dispose);

    // ── Shape the intro performance and capture it onto `verse` ──────────────
    final pads = engine.addChannel(name: 'pads');
    engine.setChannelVolume(pads, 0.4);
    engine.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );
    await tester.pumpAndSettle();

    final sm = engine.stateMachine;
    expect(sm.captureSlice(verseStateAddress, StateSliceCategory.mix), isTrue);
    expect(
      sm.captureSlice(verseStateAddress, StateSliceCategory.variables),
      isTrue,
    );

    // Author the follow-on: `verse → intro`, timed — 64 beats on the drum
    // domain, armed the moment `verse` is entered.
    expect(sm.connect(verseStateAddress, introStateAddress), isTrue);
    expect(
      sm.setTrigger(
        verseStateAddress,
        introStateAddress,
        TimedTrigger(beats: 64, domain: drumDomain),
      ),
      isTrue,
    );

    // ── A MIDI-graph branch guarded on `state.verse` ─────────────────────────
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.text('convert to graph →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('convert'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PREVIEW · 10 NOTES'), findsOneWidget);

    final graph = engine.midi.graphController;
    final branch = graph.addNodeAt(
      const TransposeTransform(semitones: 12, label: 'branch · +12'),
      const Offset(200, 360),
    );
    graph.connect(
      TransformNodeId.source,
      branch.id,
      condition: StateMatchCondition(verseStateAddress),
    );
    await tester.pumpAndSettle();
    // `intro` is live → the guard is closed.
    expect(find.textContaining('PREVIEW · 10 NOTES'), findsOneWidget);

    // ── Move the performance away, then save ─────────────────────────────────
    engine.setChannelVolume(pads, 0.9);
    engine.runtimeVariables.setValue('section', 'b');
    await tester.pumpAndSettle();

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
    expect(journal.lines, isEmpty);
    final authoredPads = controller.registry.entityAt(padsAddress)!.payload;

    // ── Fire to `verse` from live code ───────────────────────────────────────
    // The exact frame `state.verse.fire()` publishes (python/tests/
    // test_verbs.py: `('phi.ctl.state.fire', 'verse')`).
    busTap.publish('phi.ctl.state.fire', const BusString('verse'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(sm.activeStateAddress, verseStateAddress);
    expect(notices, isEmpty);

    // The captured slices applied: mix level and variable snapped back…
    final livePads = engine.channels.value.singleWhere((c) => c.name == 'pads');
    expect(livePads.volume, 0.4);
    expect(engine.runtimeVariables.byName('section')!.current, 'a');

    // …journal-free: still saved, nothing journaled, authored payloads kept.
    expect(controller.isSaved, isTrue);
    expect(journal.lines, isEmpty);
    expect(controller.registry.entityAt(padsAddress)!.payload, authoredPads);

    // The guarded branch re-routed exactly as a manual fire re-routes it.
    expect(find.textContaining('PREVIEW · 20 NOTES'), findsOneWidget);

    // `state.current` rode the shared evaluator into the interpreter.
    expect(evaluator.calls, contains("phi._sync_state_current('verse')"));

    // The timed follow-on armed on entry: a reserved clock counts toward
    // `intro` at the drum domain's tempo.
    expect(engine.stateTriggers.armedTimedTargets, [introStateAddress]);
    final timedClock = midiGateway.transports
        .where(
          (t) =>
              t.clockName ==
              '${StateTriggerScheduler.timedClockPrefix}.state.intro',
        )
        .single;
    expect(timedClock.isPlaying, isTrue);
    expect(timedClock.tempo, 124);

    // ── An early manual exit cancels the schedule ────────────────────────────
    sm.setLive(introStateAddress);
    await tester.pumpAndSettle();
    expect(engine.stateTriggers.armedTimedTargets, isEmpty);
    expect(timedClock.isPlaying, isFalse);
    // The guard closed again — the preview follows the manual entry too.
    expect(find.textContaining('PREVIEW · 10 NOTES'), findsOneWidget);

    // ── A variable-match transition re-routes the guarded branch ─────────────
    // Re-trigger `intro → verse` on `section = "b"` (authorship — re-save).
    expect(
      sm.setTrigger(
        introStateAddress,
        verseStateAddress,
        const VariableTrigger(name: 'section', value: 'b'),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('state-end-to-end'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.isSaved, isTrue);

    // The variable moving onto its value fires the transition, and the entry
    // re-applies verse's slices — `section` snaps straight back to `a`.
    engine.runtimeVariables.setValue('section', 'b');
    await tester.pumpAndSettle();
    expect(sm.activeStateAddress, verseStateAddress);
    expect(engine.runtimeVariables.byName('section')!.current, 'a');
    expect(find.textContaining('PREVIEW · 20 NOTES'), findsOneWidget);
    expect(controller.isSaved, isTrue);
    expect(journal.lines, isEmpty);

    // The State canvas followed the whole walk: `verse` wears the LIVE capsule.
    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();
    expect(find.text('● LIVE'), findsOneWidget);

    // Nothing degraded anywhere along the walk.
    expect(engine.lastStateNotice.value, isNull);
    expect(notices, isEmpty);

    await engine.dispose();
    await midiGateway.dispose();
    await busTap.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}

/// The control plane's other owning controllers, faked (cross-epic seams —
/// design `docs/design/live-coding.md` §4): this walk routes only state fires,
/// so every other port is inert and any call onto one would surface through
/// the dispatcher's notice log instead.
class _InertPorts
    implements
        ClipControlPort,
        VoiceControlPort,
        VariableControlPort,
        TempoControlPort {
  @override
  void play(EntityAddress target) {}

  @override
  void stop(EntityAddress target) {}

  @override
  void pause(EntityAddress target) {}

  @override
  void loop(EntityAddress target, {required bool on}) {}

  @override
  void stopAll() {}

  @override
  void note(EntityAddress voice, {required int pitch, int velocity = 100}) {}

  @override
  void off(EntityAddress voice, {int? pitch}) {}

  @override
  void set(String name, Object? value) {}

  @override
  void setTempo(EntityAddress domain, double bpm) {}
}
