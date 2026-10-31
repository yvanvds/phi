import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end reproduction of issue #460 through the real [PhiApp]: a project
/// whose patch holds a `.slider` is opened **at launch**, before the Patcher
/// surface has ever been mounted, and the performer then switches to the
/// Patcher.
///
/// That is the path the app takes on every start (`main` auto-reopens the most
/// recent project). The engine rebuilds the patch editor from the live
/// instance while the node-type registry is still empty — it is populated by
/// `PatcherSurface.initState` — so the slider is measured as a one-line object
/// box, shorter than the fader's 24 px thumb. Before the fix the fader's thumb
/// `clamp` got an inverted range and threw on every build.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final patchAddress = EntityAddress(
    kind: RegistryKinds.patch,
    segments: const ['faders'],
  );

  // The default project plus one patch whose saved dump holds a slider.
  void seedWithSlider(ProjectRegistry registry) {
    seedDefaultProject(registry);
    registry.createEntity(
      patchAddress,
      payload: const PatchPayload(
        dump: {
          'objects': [
            {'id': 0, 'type': Obj.gSlider, 'args': '', 'x': 64.0, 'y': 64.0},
          ],
          'cables': <Object?>[],
        },
      ).toJson(),
    );
  }

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('a slider in a project opened at launch renders on the canvas', (
    tester,
  ) async {
    // A fresh process: nothing has registered the built-in node types yet.
    NodeTypeRegistry.instance.clear();

    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      patcherGateway: FakePatcherGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedWithSlider,
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

    // The project's patch is the open one, rebuilt before the Patcher mounted.
    expect(engine.patchLibrary.openAddress, patchAddress);

    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PatcherNodeView), findsOneWidget);
    final fader = find.descendant(
      of: find.byType(PatcherNodeView),
      matching: find.byType(PhiFader),
    );
    expect(fader, findsOneWidget);

    // A few more frames: the fault was per build, not a one-off.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);

    await engine.dispose();
    await gateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
