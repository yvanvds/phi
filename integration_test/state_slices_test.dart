import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/state_slice_category.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/midi/clip_transport_row.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of slice capture-from-live (issue #242) through the real
/// [PhiApp]: with the seeded clip *actually playing* (transport row), a bus
/// materialised at a live level, runtime variables defined, and the seeded
/// `domain.drum` tempo, capturing each category onto `state.intro` reflects
/// the live performance exactly; a per-entry edit trims the capture without
/// recapturing; a save + second launch round-trips the captured slices
/// identically; and deleting a captured referent degrades gracefully at
/// resolve time — the rest applies and the missing address is surfaced.
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

  testWidgets('slices capture the live performance, round-trip a save, and '
      'degrade gracefully on a deleted referent', (tester) async {
    const dir = '/projects/slices.phi';
    final phraseA = EntityAddress.parse('clip.phrase_a');
    final drumDomain = EntityAddress.parse('domain.drum');
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: play, shape the live state, capture, save ----------------
    final midiGateway1 = FakeMidiGateway();
    final engine1 = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway1,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final appSettings1 = AppSettingsController(settings);
    final controller1 = ProjectController(
      session: session1,
      settings: appSettings1,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        key: const ValueKey('launch-1'),
        engine: engine1,
        session: session1,
        projectController: controller1,
        directoryPicker: FakeProjectDirectoryPicker(newLocationPath: dir),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Shape the live mix: a real materialised bus at a set level, muted.
    final pads = engine1.addChannel(name: 'pads');
    engine1.setChannelVolume(pads, 0.4);
    engine1.setChannelMuted(pads, muted: true);
    await tester.pumpAndSettle();

    // Define runtime variables — the store MIDI-graph guards read.
    engine1.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );
    engine1.runtimeVariables.define(name: 'mode', values: ['lead']);

    // Start the seeded clip from the MIDI surface's transport row — the
    // capture must see what is *actually sounding*.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine1.midi.isPlaying, isTrue);

    // Capture every category onto the live state.
    final sm1 = engine1.stateMachine;
    for (final category in StateSliceCategory.values) {
      expect(sm1.captureSlice(introStateAddress, category), isTrue);
    }

    // The capture reflects the live performance exactly (issue done-when).
    final captured = stateDoc(controller1, introStateAddress).slices;
    expect(captured.clips, [ClipSliceEntry(clip: phraseA)]);
    final padsAddress = EntityAddress.parse('mix.pads');
    expect(
      captured.mix,
      contains(MixSliceEntry(bus: padsAddress, volume: 0.4, muted: true)),
    );
    expect(captured.variables, {'section': 'a', 'mode': 'lead'});
    expect(captured.tempos, [TempoSliceEntry(domain: drumDomain, bpm: 124)]);

    // Per-entry edit: trim one variable without recapturing.
    sm1.removeVariableSliceEntry(introStateAddress, 'mode');
    expect(stateDoc(controller1, introStateAddress).slices.variables, {
      'section': 'a',
    });

    // Stop the transport so the app can settle, then save via the menu.
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump(const Duration(milliseconds: 50));
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
    expect(controller1.isSaved, isTrue);

    final savedIntro = stateDoc(controller1, introStateAddress);

    // --- Launch 2: reload, verify the round-trip, delete a referent ---------
    final midiGateway2 = FakeMidiGateway();
    final engine2 = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    final appSettings2 = AppSettingsController(settings);
    final controller2 = ProjectController(
      session: session2,
      settings: appSettings2,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        key: const ValueKey('launch-2'),
        engine: engine2,
        session: session2,
        projectController: controller2,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Launch 1 is unmounted now — release its resources.
    await engine1.dispose();
    await midiGateway1.dispose();
    controller1.dispose();
    appSettings1.dispose();
    session1.dispose();

    // The captured + edited slices round-tripped identically.
    expect(stateDoc(controller2, introStateAddress), savedIntro);

    // Delete the captured bus through the real remove path: the slice now
    // references a deleted entity, and resolution applies the rest while
    // surfacing the missing address (issue done-when; #243 raises the notice).
    final pads2 = engine2.channels.value.singleWhere((c) => c.name == 'pads');
    engine2.removeChannel(pads2);
    await tester.pumpAndSettle();

    final resolution = engine2.stateMachine.resolveSlicesOf(introStateAddress);
    expect(resolution.missing, {padsAddress});
    expect(resolution.applicable.mix, isEmpty);
    expect(resolution.applicable.clips, [ClipSliceEntry(clip: phraseA)]);
    expect(resolution.applicable.variables, {'section': 'a'});
    expect(resolution.applicable.tempos, [
      TempoSliceEntry(domain: drumDomain, bpm: 124),
    ]);

    await engine2.dispose();
    await midiGateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
