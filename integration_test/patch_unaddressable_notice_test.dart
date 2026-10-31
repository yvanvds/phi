import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
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
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/diagnostics/phi_toast.dart';
import 'package:yse/yse.dart' show Patcher;

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that a patch whose address is too long for the engine to
/// name its native patcher is **not silently unreachable** (issue #452):
/// opening a project that already holds one, through the real [PhiApp],
/// toasts a warning naming the patch and logs it — while the patch itself
/// still opens.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Two valid segments whose dotted path is one past the engine's cap.
  final longPatch = EntityAddress(
    kind: RegistryKinds.patch,
    segments: ['a' * 30, 'b' * (Patcher.maxNameLength - 30)],
  );

  void seedWithLongPatch(ProjectRegistry registry) {
    seedDefaultProject(registry);
    registry.createEntity(longPatch, payload: PatchPayload.empty.toJson());
  }

  testWidgets('opening an over-long patch address toasts and logs a warning', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final patcher = FakePatcherGateway();
    final engine = PhiEngine(
      gateway,
      patcherGateway: patcher,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedWithLongPatch,
      autosaveIntervalOverride: const Duration(hours: 1),
    );
    final notices = NoticeCenter.build();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/long.phi',
        ),
        autoStartProject: true,
        noticeCenter: notices,
      ),
    );
    await tester.pumpAndSettle();

    // The patch still opened — it is only its bus name that could not stick.
    expect(engine.patches.isOpen(longPatch), isTrue);

    // The user is told, on screen …
    expect(find.byType(PhiToast), findsOneWidget);
    expect(find.textContaining('cannot be reached on the bus'), findsOneWidget);
    // … and in the unified log, at warning level, naming the patch.
    final logged = notices.log.entries.where(
      (e) => e.source == LogSource.app && e.text.contains(longPatch.format()),
    );
    expect(logged, isNotEmpty);
    expect(logged.last.level, LogLevel.warning);

    notices.dispose();
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
