import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/design/widgets/dialog/delete_impact_dialog.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of issue #171 driven through the real [PhiApp]:
///
/// 1. **Layout-aware master meters (design §6).** The master strip renders one
///    meter bar per speaker output — two on the fake gateway's default stereo —
///    and re-derives the bar count **without a restart** when the device layout
///    swaps to 5.1 (six bars) mid-session.
/// 2. **Return delete-impact (design §4, §7).** The performer wires an aux send
///    from a channel to a return, then deletes the return: the delete-impact
///    dialog warns, listing the sender, and confirming clears that send before
///    the return is removed.
///
/// All against in-memory fakes — no native audio hardware, filesystem or dialog.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  EntityAddress mix(List<String> segments) =>
      EntityAddress(kind: RegistryKinds.mix, segments: segments);

  testWidgets('master meters follow the layout; return delete warns & clears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
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
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    /// Advances the telemetry timer and settles the rebuild so the master strip
    /// re-reads the gateway's output count + per-output peaks.
    Future<void> tickTelemetry() async {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
    }

    // ── 1. Master meters follow the layout ───────────────────────────────────

    // The fake gateway boots stereo — the master strip shows exactly two bars.
    gateway.masterPeakOutputs = [0.3, 0.7];
    await tickTelemetry();
    expect(find.byKey(ChannelStrip.outputMeterKey(0)), findsOneWidget);
    expect(find.byKey(ChannelStrip.outputMeterKey(1)), findsOneWidget);
    expect(find.byKey(ChannelStrip.outputMeterKey(2)), findsNothing);

    // The device/layout swaps to 5.1 at runtime; the meter re-derives its bar
    // count on the next tick — no restart.
    gateway.masterOutputCountValue = 6;
    gateway.masterPeakOutputs = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
    await tickTelemetry();
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(ChannelStrip.outputMeterKey(i)), findsOneWidget);
    }
    expect(find.byKey(ChannelStrip.outputMeterKey(6)), findsNothing);

    // ── 2. Return delete-impact ──────────────────────────────────────────────

    Future<void> addFromMenu(String item) async {
      await tester.tap(
        find.descendant(of: find.byType(MixSurface), matching: find.text('+')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    await addFromMenu('add channel'); // ch_1
    await addFromMenu('add return'); // slugs to return_ (return is reserved)
    expect(engine.channels.value.map((c) => c.name), ['ch_1']);
    expect(engine.returns.value.map((c) => c.name), ['return_']);

    // Wire a send from ch_1 to the return through the add-send picker.
    await tester.tap(find.byKey(MixSurface.addSendKey('ch_1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addSendKey('ch_1')),
            matching: find.text('return_'),
          )
          .last,
    );
    await tester.pumpAndSettle();

    final ch1 = engine.channels.value.single;
    expect(engine.channelSends(ch1), hasLength(1));
    expect(engine.channelSends(ch1).single.to, mix(['return_']));

    // Delete the return: the delete-impact dialog warns, listing the sender.
    await tester.tap(find.byKey(MixSurface.returnRemoveKey('return_')));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteImpactDialog), findsOneWidget);
    expect(find.textContaining('mix.ch_1'), findsOneWidget);
    // Nothing removed until the performer confirms.
    expect(engine.returns.value, hasLength(1));
    expect(engine.channelSends(ch1), hasLength(1));

    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    // Confirmed: the return is gone, its section vanishes, and the sender's send
    // was cleared — no dangling reference remains.
    expect(engine.returns.value, isEmpty);
    expect(find.byKey(MixSurface.returnsSectionKey), findsNothing);
    expect(engine.channelSends(ch1), isEmpty);

    // Release resources.
    await engine.dispose();
    await gateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
