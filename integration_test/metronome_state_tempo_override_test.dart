import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/state_transition.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/metronome_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/top_toolbar/metronome_control.dart';
import 'package:phi/shell/top_toolbar/metronome_popover.dart';
import 'package:phi/surfaces/state/state_canvas.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that a metronome click follows a **state-applied domain
/// tempo override** (issue #331) through the real [PhiApp].
///
/// A fresh project seeds `domain.drum @ 124` and the `intro → verse` state pair.
/// The toolbar click is enabled and bound to `drum`, so it paces at 124. Firing
/// `intro → verse` with a captured tempos slice overriding `drum` to 90 re-paces
/// the running click to 90 — exactly as it re-paces the subscribed clip sessions
/// — while the authored `domain.drum` payload keeps its 124. A New project then
/// clears the live overrides, and the click falls back to the authored tempo.
/// All against in-memory fakes; no native library or filesystem is touched.
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

  testWidgets('a bound metronome click re-paces to a state-applied domain '
      'tempo override, then falls back to authored on project swap', (
    tester,
  ) async {
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
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/metronome-override.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // --- Enable the click and bind it to `drum @ 124` from the toolbar --------
    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    expect(engine.metronome.enabled, isTrue);

    await tester.tap(find.byKey(MetronomeControl.popoverButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MetronomePopover.domainPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('drum · 124 bpm'));
    await tester.pumpAndSettle();
    // Dismiss the popover.
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();

    final click = midiGateway.transports.firstWhere(
      (t) => t.clockName == MetronomeController.defaultClockName,
    );
    expect(engine.metronome.domainName, 'drum');
    expect(click.isPlaying, isTrue);
    expect(click.tempo, 124, reason: 'paces from the authored drum tempo');

    // --- Capture a tempo override onto `verse` --------------------------------
    // A state application lays `drum → 90` over the authored 124.
    final verseDoc = stateDoc(controller, verseStateAddress);
    controller.registry.updateEntityPayload(
      verseStateAddress,
      verseDoc.copyWith(
        slices: verseDoc.slices.copyWith(
          tempos: [TempoSliceEntry(domain: drumDomain, bpm: 90)],
        ),
      ),
    );

    // --- Fire intro → verse from the State canvas -----------------------------
    final sm = engine.stateMachine;
    await tester.tap(railFor(SurfaceId.state));
    await tester.pumpAndSettle();
    sm.toggleArmed(
      StateTransition(source: introStateAddress, target: verseStateAddress),
    );
    await tester.pump();
    await tester.tap(onCanvas('verse'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(sm.activeStateAddress, verseStateAddress);

    // The click tracked the applied override, re-pacing through the clock
    // binding without ever re-pushing its note list…
    expect(engine.midi.domainTempoOverride('drum'), 90);
    expect(click.tempo, 90, reason: 'the click follows the applied override');
    // …and the authored `domain.drum` tempo is untouched (journal-free): the
    // picker still resolves the authored 124 from the live registry.
    expect(engine.metronome.boundDomain?.tempo, 124);

    // --- Project swap clears the overrides → fall back to authored tempo ------
    controller.newProject();
    await tester.pumpAndSettle();
    expect(engine.midi.domainTempoOverride('drum'), isNull);
    // Same running click (performance state survives the swap), re-paced back to
    // the fresh project's authored drum tempo.
    expect(engine.metronome.enabled, isTrue);
    expect(click.tempo, 124, reason: 'authored tempo restored on project swap');

    // Wind down.
    engine.metronome.setEnabled(false);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
