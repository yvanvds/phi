import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/log/crash_report.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/commands/command_palette.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';

import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the report bundle + crash surfacing (issue #272, design
/// `docs/design/diagnostics.md` §6) driven through the real [PhiApp]: the
/// "Copy Diagnostics" palette command assembles the paste-ready block and writes
/// it to the clipboard, and a crashed previous session surfaces a notice linking
/// its log file on the next boot. All against fakes — no `libyse.dll`, no GL.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder paletteField() => find.descendant(
    of: find.byType(CommandPalette),
    matching: find.byType(TextField),
  );

  Future<void> pressCtrlShiftP(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('the Copy Diagnostics command writes the bundle to the clipboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = FakeYseGateway()..engineVersionValue = 'yse-test 9.9.1';
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

    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, noticeCenter: notices),
    );
    await tester.pumpAndSettle();

    // Seed a couple of log lines the bundle must carry (log-only, so no toast).
    notices.recorder.engine('audio device opened');
    notices.recorder.app('project saved');
    await tester.pump();

    // Invoke the command through the real palette.
    await pressCtrlShiftP(tester);
    await tester.enterText(paletteField(), 'Copy Diag');
    await tester.pumpAndSettle();
    expect(find.text('Copy Diagnostics'), findsOneWidget);
    await tester.tap(find.text('Copy Diagnostics'));
    await tester.pumpAndSettle();

    // The palette closed and the clipboard holds the stable-ordered bundle,
    // including the live facts and the seeded log tail.
    expect(find.byType(CommandPalette), findsNothing);
    expect(copied, isNotNull);
    expect(copied, contains('Phi diagnostics'));
    expect(copied, contains('App version:'));
    expect(copied, contains('libYSE version: yse-test 9.9.1'));
    expect(copied, contains('Open project: (no project open)'));
    expect(copied, contains('Log (last'));
    expect(copied, contains('audio device opened'));
    expect(copied, contains('project saved'));

    // The copy confirms through the notice channel (toast + log entry).
    expect(find.text('Diagnostics copied to clipboard'), findsOneWidget);

    notices.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  testWidgets('a crashed previous session surfaces a notice linking its log', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const previousLog = 'phi-20260722-090000-000.log';
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final notices = NoticeCenter.build();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        noticeCenter: notices,
        // The boot found no clean-shutdown marker → the previous session crashed.
        crashReport: Future<CrashReport?>.value(
          const CrashReport(previousLogName: previousLog),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A toast surfaces on first frame, naming the crashed session's log file.
    expect(find.textContaining('logs/$previousLog'), findsOneWidget);
    expect(find.textContaining('ended unexpectedly'), findsOneWidget);

    // And nothing vanishes without a trace: the same notice landed in the log at
    // warning level, tagged app.
    final logged = notices.log.entries.where(
      (e) =>
          e.source == LogSource.app &&
          e.level == LogLevel.warning &&
          e.text.contains(previousLog),
    );
    expect(logged, isNotEmpty);

    notices.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
