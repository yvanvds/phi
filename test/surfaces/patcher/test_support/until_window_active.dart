import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// How long, in real time, [untilWindowActive] waits for an inactive window
/// to come back before the caller types anyway.
///
/// Long enough for a live desktop to hand focus back to the test window
/// (a notification closing, the compositor settling a freshly mapped
/// window); short, because under `xvfb-run` the window may never come back
/// and each search used to wait out a 10 s cap, about 13 s with the pumps
/// (#542).
const windowActiveGrace = Duration(seconds: 1);

/// Waits, in real time, up to [windowActiveGrace] until the app is
/// `resumed`: its window has OS focus, so a focused field's text input
/// connection stays open (#527). Returns early on `resumed`, and gives up
/// quietly after the grace: the callers ([searchTutorials],
/// [typeIntoField]) check that the text landed and type again if it did not.
///
/// Why typing cares: on a desktop, when the app goes `inactive` the
/// [FocusManager] parks the primary focus on the root scope (closing the
/// field's text input connection) and gives it back only when the window is
/// `resumed` again. Typing into a field whose connection is closed is dropped
/// silently.
Future<void> untilWindowActive(WidgetTester tester) async {
  final waited = Stopwatch()..start();
  while (waited.elapsed < windowActiveGrace) {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
