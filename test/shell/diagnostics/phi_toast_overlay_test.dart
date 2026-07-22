import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/diagnostics/phi_toast.dart';
import 'package:phi/shell/diagnostics/phi_toast_overlay.dart';

void main() {
  Widget host(NoticeCenter center) => MaterialApp(
    home: Scaffold(body: PhiToastOverlay(controller: center.toasts)),
  );

  testWidgets('a notice renders a toast AND logs the entry (the pairing)', (
    tester,
  ) async {
    final center = NoticeCenter.build(
      toastDuration: const Duration(seconds: 2),
    );
    await tester.pumpWidget(host(center));

    center.notice('device unavailable', level: LogLevel.warning);
    await tester.pump(); // entry frame
    await tester.pump(const Duration(milliseconds: 200)); // entry animation

    // Toast on screen …
    expect(find.text('device unavailable'), findsOneWidget);
    expect(find.byType(PhiToast), findsOneWidget);
    // … and the same call left a log entry.
    expect(center.log.entries.single.text, 'device unavailable');

    center.dispose();
  });

  testWidgets('the toast auto-dismisses after its lifespan', (tester) async {
    final center = NoticeCenter.build(
      toastDuration: const Duration(seconds: 2),
    );
    await tester.pumpWidget(host(center));

    center.notice('transient');
    await tester.pump();
    expect(find.text('transient'), findsOneWidget);

    // Past the 2 s lifespan the overlay dismisses it (timer lives in the entry
    // widget's state, so a live tree tears it down cleanly).
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('transient'), findsNothing);
    expect(center.toasts.visible, isEmpty);

    center.dispose();
  });

  testWidgets('the overlay is non-interactive (clicks pass through)', (
    tester,
  ) async {
    final center = NoticeCenter.build();
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => tapped = true,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              Positioned.fill(
                child: PhiToastOverlay(controller: center.toasts),
              ),
            ],
          ),
        ),
      ),
    );

    center.notice('over the button');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Tap where the toast sits (bottom-centre) — the click reaches the button
    // beneath because the overlay ignores pointers.
    await tester.tap(find.text('over the button'), warnIfMissed: false);
    expect(tapped, isTrue);

    center.dispose();
  });
}
