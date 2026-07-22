import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/log_filter_bar.dart';
import 'package:phi/shell/diagnostics/log_panel.dart';
import 'package:phi/shell/diagnostics/log_panel_toggle.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';

import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the log panel drawer (issue #270, design
/// `docs/design/diagnostics.md` §4, §5) driven through the real [PhiApp]: the
/// status-bar toggle and `Ctrl+J` open the drawer over the shared unified log,
/// the filters/search narrow it, copy writes paste-ready text, and the
/// status-bar error badge opens filtered to errors and clears. All against
/// fakes — no `libyse.dll`, no GL.
///
/// Entries are seeded through the recorder's log-only sources (engine / python /
/// app), so no toast rides along to double a text finder — the notice-channel's
/// toast+log path has its own end-to-end test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The status strip is a full-width bar; the LOG toggle needs more than the
  // 800px test default (as the other real-app tests do).
  Future<void> pumpApp(
    WidgetTester tester, {
    required NoticeCenter notices,
    required PhiEngine engine,
    required SessionState session,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, noticeCenter: notices),
    );
    await tester.pumpAndSettle();
  }

  Finder filterChip(String label) => find.descendant(
    of: find.byType(LogFilterBar),
    matching: find.text(label),
  );

  // Log rows live inside the LogPanel; scoping here keeps a finder off any
  // unrelated chrome text.
  Finder rowContaining(String text) => find.descendant(
    of: find.byType(LogPanel),
    matching: find.textContaining(text),
  );

  testWidgets(
    'the status-bar toggle opens the log; filter and search narrow it',
    (tester) async {
      final gateway = FakeYseGateway();
      final engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 20),
      );
      final session = SessionState();
      final notices = NoticeCenter.build();

      await pumpApp(tester, notices: notices, engine: engine, session: session);

      // Seed two non-error lines so the toggle opens plainly (no error badge to
      // divert it to an errors-only view).
      notices.recorder.engine('audio device opened');
      notices.recorder.app('project saved');
      await tester.pump();

      // The drawer is closed; the toggle lives in the status bar.
      expect(find.byType(LogPanel), findsNothing);
      expect(find.byKey(LogPanelToggle.toggleKey), findsOneWidget);

      // Open it — a plain toggle shows every source.
      await tester.tap(find.byKey(LogPanelToggle.toggleKey));
      await tester.pumpAndSettle();
      expect(find.byType(LogPanel), findsOneWidget);
      expect(rowContaining('audio device opened'), findsOneWidget);
      expect(rowContaining('project saved'), findsOneWidget);

      // A Python traceback arrives while the drawer is open (so it does not
      // badge) and shows live.
      notices.recorder.python('Traceback:\nNameError: name "gain"');
      await tester.pump();
      expect(rowContaining('NameError'), findsOneWidget);

      // Filter to errors: only the Python traceback survives.
      await tester.tap(filterChip('ERROR'));
      await tester.pumpAndSettle();
      expect(rowContaining('NameError'), findsOneWidget);
      expect(rowContaining('audio device opened'), findsNothing);

      // Clear filters, then search for a substring.
      await tester.tap(find.byKey(LogPanel.clearKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(LogFilterBar.searchFieldKey), 'saved');
      await tester.pumpAndSettle();
      expect(rowContaining('project saved'), findsOneWidget);
      expect(rowContaining('audio device opened'), findsNothing);

      notices.dispose();
      session.dispose();
      await engine.dispose();
      await gateway.dispose();
    },
  );

  testWidgets('copy writes the visible filtered log to the clipboard', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final notices = NoticeCenter.build();

    // Capture Clipboard.setData off the platform channel.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpApp(tester, notices: notices, engine: engine, session: session);

    // Two non-error lines → plain open showing both; copy grabs the visible set.
    notices.recorder.engine('device opened');
    notices.recorder.app('project saved');
    await tester.pump();

    await tester.tap(find.byKey(LogPanelToggle.toggleKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LogPanel.copyKey));
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('device opened'));
    expect(copied, contains('project saved'));

    notices.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  testWidgets('the error badge opens the log filtered to errors and clears', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final notices = NoticeCenter.build();

    await pumpApp(tester, notices: notices, engine: engine, session: session);

    // Two errors land while the drawer is closed → the toggle badges "2".
    notices.recorder.app('first failure', level: LogLevel.error);
    notices.recorder.app('second failure', level: LogLevel.error);
    notices.recorder.app('just info');
    await tester.pump();

    expect(find.byKey(LogPanelToggle.badgeKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(LogPanelToggle.badgeKey),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    // Tapping the badged toggle opens filtered to errors and clears the badge.
    await tester.tap(find.byKey(LogPanelToggle.toggleKey));
    await tester.pumpAndSettle();

    expect(find.byType(LogPanel), findsOneWidget);
    expect(find.byKey(LogPanelToggle.badgeKey), findsNothing);
    expect(rowContaining('first failure'), findsOneWidget);
    expect(rowContaining('second failure'), findsOneWidget);
    // The info line is filtered out by the errors-only view.
    expect(rowContaining('just info'), findsNothing);

    notices.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  testWidgets('Ctrl+J toggles the log drawer', (tester) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final notices = NoticeCenter.build();

    await pumpApp(tester, notices: notices, engine: engine, session: session);

    Future<void> pressCtrlJ() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    expect(find.byType(LogPanel), findsNothing);
    await pressCtrlJ();
    expect(find.byType(LogPanel), findsOneWidget);
    await pressCtrlJ();
    expect(find.byType(LogPanel), findsNothing);

    notices.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
