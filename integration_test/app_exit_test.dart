import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/log/session_log.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';

import '../test/domain/log/test_doubles/fake_log_file_store.dart';
import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the OS close path (issue #462) through the real
/// [PhiApp]: an exit request — what the GTK embedder sends on the window's
/// `delete-event`, and the Windows one on `WM_CLOSE` — runs the close guard,
/// and a granted exit stops the engine and writes the clean-shutdown marker
/// *before* answering, because the embedder ends the process right after with
/// no widget teardown. A vetoed exit does neither.
///
/// The request is driven with [WidgetsBinding.handleRequestAppExit], the same
/// entry the platform channel calls, so the embedder never actually quits the
/// test process.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PhiEngine engine;
  late SessionState session;
  late AppSettingsController settings;
  late ProjectController controller;
  late FakeLogFileStore logFiles;
  late SessionLog sessionLog;

  setUp(() async {
    engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    session = SessionState();
    settings = AppSettingsController(FakeAppSettingsStore());
    final store = FakeProjectStore();
    controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => FakeJournalStore(),
      autosaveIntervalOverride: const Duration(hours: 1),
    );
    logFiles = FakeLogFileStore();
    sessionLog = SessionLog(files: logFiles);
    await sessionLog.boot();
  });

  tearDown(() async {
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/exit.phi',
        ),
        sessionLog: sessionLog,
      ),
    );
    await tester.pumpAndSettle();
    expect(engine.isStarted, isTrue);
    expect(logFiles.marker, isNull, reason: 'boot consumes no marker here');
  }

  testWidgets('closing a clean project stops the engine and marks a clean '
      'shutdown', (tester) async {
    await pumpApp(tester);

    final response = await tester.binding.handleRequestAppExit();

    expect(response, AppExitResponse.exit);
    expect(engine.isStarted, isFalse);
    expect(logFiles.marker, startsWith('clean shutdown'));
  });

  testWidgets('keep working on a dirty project vetoes the close and leaves the '
      'session running', (tester) async {
    await pumpApp(tester);
    session.setTempo(132);
    await tester.pump();
    expect(controller.isDirty.value, isTrue);

    final pending = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('keep working'));
    await tester.pumpAndSettle();

    expect(await pending, AppExitResponse.cancel);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(engine.isStarted, isTrue);
    expect(logFiles.marker, isNull);
  });

  testWidgets('discarding a dirty project exits through the orderly shutdown', (
    tester,
  ) async {
    await pumpApp(tester);
    session.setTempo(132);
    await tester.pump();

    final pending = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    await tester.tap(find.text('discard'));
    await tester.pumpAndSettle();

    expect(await pending, AppExitResponse.exit);
    expect(engine.isStarted, isFalse);
    expect(logFiles.marker, startsWith('clean shutdown'));
  });
}
