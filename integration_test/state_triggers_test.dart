import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/state_trigger_scheduler.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/state/state_canvas.dart';
import 'package:phi/surfaces/state/state_transition_badge.dart';
import 'package:phi/surfaces/state/state_trigger_editor.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the transition triggers (issue #244) through the real
/// [PhiApp]: the canvas badges the seeded transition's kind, tap-to-arm now
/// lives on the badge, tapping the curve opens the trigger editor, and the
/// edited trigger *behaves* — a timed trigger arms a reserved domain-paced
/// clock exactly while its source is the entered live state, a variable
/// trigger fires the moment the runtime variable changes onto its value, and
/// the `phi` control-plane seam fires by name. The timed *downbeat* itself is
/// a timing behaviour proven against a fake clock in the scheduler's unit
/// tests (the count-in precedent) — here we prove the visible arming,
/// cancellation and firing the real widgets drive.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  StateDocument stateDoc(ProjectController controller, EntityAddress address) {
    final payload = controller.registry.entityAt(address)!.payload!;
    return payload is StateDocument
        ? payload
        : StateDocument.fromJson((payload as Map).cast());
  }

  testWidgets('badges, tap-to-arm on the badge, the trigger editor, and the '
      'timed / variable / code trigger behaviour', (tester) async {
    final drumDomain = EntityAddress.parse('domain.drum');
    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    engine.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );

    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();

    // ── The seeded manual transition wears its badge ─────────────────────────
    expect(find.byType(StateTransitionBadge), findsOneWidget);
    expect(find.text('MANUAL'), findsOneWidget);

    // ── Tap-to-arm lives on the badge now (design §5) ────────────────────────
    await tester.tap(find.byType(StateTransitionBadge));
    await tester.pump();
    expect(find.text('▲ ARMED · MANUAL'), findsOneWidget);
    await tester.tap(find.byType(StateTransitionBadge));
    await tester.pump();
    expect(find.text('▲ ARMED · MANUAL'), findsNothing);

    // Arm again and fire by tapping the target node — `verse` is *entered*.
    await tester.tap(find.byType(StateTransitionBadge));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(StateCanvas),
        matching: find.text('verse'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.stateMachine.activeStateAddress, verseStateAddress);

    // Re-enter `intro` explicitly — the entry that will arm its timed trigger.
    engine.stateMachine.setLive(introStateAddress);
    await tester.pumpAndSettle();
    expect(engine.stateMachine.activeStateAddress, introStateAddress);

    // ── Curve tap opens the editor; author a timed trigger ───────────────────
    // The seeded curve runs along y = 188 between the nodes; x = 292 is on
    // the curve but clear of the badge at its midpoint (340, 188).
    final origin = tester.getTopLeft(find.byType(StateCanvas));
    await tester.tapAt(origin + const Offset(292, 188));
    await tester.pumpAndSettle();
    expect(find.byType(StateTriggerEditor), findsOneWidget);

    await tester.tap(find.byKey(StateTriggerEditor.kindKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('timed').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(StateTriggerEditor.beatsKey), '64');
    await tester.tap(find.byKey(StateTriggerEditor.domainKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('drum · 124 bpm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StateTriggerEditor.saveKey));
    await tester.pumpAndSettle();

    // The authored payload carries the trigger, the badge follows, and —
    // because `intro` is the *entered* live state — a reserved clock is
    // already counting toward `verse` at the drum domain's tempo.
    expect(
      stateDoc(controller, introStateAddress).transitions.single.trigger,
      TimedTrigger(beats: 64, domain: drumDomain),
    );
    expect(find.text('TIMED'), findsOneWidget);
    expect(engine.stateTriggers.armedTimedTargets, [verseStateAddress]);
    final timedClock = midiGateway.transports
        .where(
          (t) =>
              t.clockName ==
              '${StateTriggerScheduler.timedClockPrefix}.state.verse',
        )
        .single;
    expect(timedClock.isPlaying, isTrue);
    expect(timedClock.tempo, 124);

    // ── Re-edit to a variable trigger — the schedule cancels ─────────────────
    await tester.tapAt(origin + const Offset(292, 188));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StateTriggerEditor.kindKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('variable').last);
    await tester.pumpAndSettle();
    // Name defaults to the defined `section`; pick the firing value.
    await tester.tap(find.byKey(StateTriggerEditor.valueKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StateTriggerEditor.saveKey));
    await tester.pumpAndSettle();

    expect(find.text('VARIABLE'), findsOneWidget);
    expect(engine.stateTriggers.armedTimedTargets, isEmpty);
    expect(timedClock.isPlaying, isFalse, reason: 'the timed schedule died');
    expect(
      stateDoc(controller, introStateAddress).transitions.single.trigger,
      const VariableTrigger(name: 'section', value: 'b'),
    );

    // ── The variable moving onto its value fires the transition ──────────────
    engine.runtimeVariables.setValue('section', 'b');
    await tester.pumpAndSettle();
    expect(engine.stateMachine.activeStateAddress, verseStateAddress);
    expect(find.text('● LIVE'), findsOneWidget);

    // ── The code seam fires by name through the control plane's port ─────────
    engine.stateMachine.connect(verseStateAddress, introStateAddress);
    await tester.pump();
    expect(engine.stateTriggers.fireTo('intro'), isTrue);
    await tester.pumpAndSettle();
    expect(engine.stateMachine.activeStateAddress, introStateAddress);

    // Nothing degraded anywhere along the walk.
    expect(engine.lastStateNotice.value, isNull);

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
