import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/diagnostics/phi_toast.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_code_evaluator.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the notice channel (design `docs/design/diagnostics.md`
/// §2, §3) driven through the real [PhiApp]: a shipped ad-hoc notice site (the
/// audio device fallback) now surfaces a toast *and* a log entry, and a Python
/// traceback lands in the same unified log.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  ProjectController buildController({
    required SessionState session,
    required AppSettingsController settings,
  }) => ProjectController(
    session: session,
    settings: settings,
    storeFactory: (_) => FakeProjectStore(),
    journalStoreFactory: (_) => FakeJournalStore(),
    autosaveIntervalOverride: const Duration(hours: 1),
  );

  testWidgets('a device fallback toasts AND logs through the channel', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Unplugged Interface',
        ),
      ),
    );
    final settings = AppSettingsController(settingsStore);
    final controller = buildController(session: session, settings: settings);
    final notices = NoticeCenter.build();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
        noticeCenter: notices,
      ),
    );
    await tester.pumpAndSettle();

    // The fallback surfaced a toast …
    expect(find.byType(PhiToast), findsOneWidget);
    expect(find.textContaining('not available'), findsOneWidget);
    // … and the same notice landed in the unified log as an app warning.
    final logged = notices.log.entries.where(
      (e) => e.source == LogSource.app && e.text.contains('not available'),
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

  testWidgets('a Python traceback lands in the log at error level', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final evaluator = FakeCodeEvaluator();
    final notices = NoticeCenter.build();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        codeEvaluator: evaluator,
        noticeCenter: notices,
      ),
    );
    await tester.pumpAndSettle();

    // The interpreter raises — the same stream the Code strip reads (§2).
    evaluator.emit(
      const EvalStderr(
        'Traceback (most recent call last):\n'
        'NameError: name "gain" is not defined',
      ),
    );
    await tester.pump();

    final python = notices.log.entries.where(
      (e) => e.source == LogSource.python,
    );
    expect(python, hasLength(1));
    expect(python.single.level, LogLevel.error);
    expect(python.single.text, contains('NameError'));

    notices.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
