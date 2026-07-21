import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/metronome_controller.dart';
import 'package:phi/shell/top_toolbar/metronome_control.dart';
import 'package:phi/shell/top_toolbar/metronome_popover.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the metronome (issue #262) through the real workstation.
///
/// A fresh project seeds `domain.drum @ 124`. Driving the top-toolbar click
/// control — enable, then bind it to the drum domain from the popover — the
/// click session runs on its own reserved clock: a one-bar pattern looping at
/// the bound domain's tempo, re-paced when the domain (or the meter) changes,
/// and stopped when the toggle turns off. All against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the toolbar click runs a session on a chosen domain', (
    tester,
  ) async {
    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final controller = ProjectController(
      session: session,
      settings: AppSettingsController(FakeAppSettingsStore()),
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
          newLocationPath: '/projects/metronome.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // The seeded project's domains reached the metronome picker.
    expect(
      engine.metronome.availableDomains.map((d) => d.name),
      contains('drum'),
    );

    // The click reserved transport with a one-bar loop.
    MetronomeController metronome() => engine.metronome;
    const clickClock = MetronomeController.defaultClockName;

    // Enable the click from the toolbar toggle.
    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    expect(metronome().enabled, isTrue);

    final click = midiGateway.transports.firstWhere(
      (t) => t.clockName == clickClock,
    );
    expect(click.isPlaying, isTrue);
    expect(click.loopBeats, 4);
    expect(click.events, hasLength(4));

    // Bind the click to `drum @ 124` from the popover — it re-paces live.
    await tester.tap(find.byKey(MetronomeControl.popoverButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MetronomePopover.domainPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('drum · 124 bpm'));
    await tester.pumpAndSettle();

    expect(metronome().domainName, 'drum');
    expect(click.tempo, 124);

    // Changing the meter re-paces the loop window (no re-push of the clock rate).
    await tester.tap(find.byKey(MetronomePopover.beatsPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 / beat'));
    await tester.pumpAndSettle();
    expect(click.loopBeats, 3);
    expect(click.events, hasLength(3));

    // Dismiss the popover, then turn the click off — the session stops.
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    expect(metronome().enabled, isFalse);
    expect(click.isPlaying, isFalse);

    session.dispose();
    await engine.dispose();
  });
}
