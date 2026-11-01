import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_browser.dart';

/// **The** way a tutorial integration test opens a tutorial (issue #527).
///
/// Types [type] into the Tutorials browser's search field
/// ([PatchTutorialBrowser.searchKey]), checks the field really holds it, then
/// taps the type's entry and settles. The browser is a `ListView` that builds
/// only the entries near its viewport (#524), so searching is what makes the
/// entry exist however long the index grows. The palette's Tutorials tab must
/// already be showing. What the opened tutorial looks like is left to the
/// caller to check.
///
/// Every tutorial test (`integration_test/patcher_*_tutorials_test.dart`)
/// goes through this helper; new ones should too, rather than typing into the
/// field themselves:
///
/// ```dart
/// import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';
///
/// await openTutorialBySearch(tester, '.metro');
/// expect(engine.patchLibrary.tutorial!.slug, 'metro');
/// ```
Future<void> openTutorialBySearch(WidgetTester tester, String type) async {
  await searchTutorials(tester, type);
  final entry = find.byKey(PatchTutorialBrowser.entryKey(type));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

/// Types [query] into the Tutorials browser's search field and fails the test
/// unless the field ends up holding it.
///
/// Why this is more than `tap` + `enterText` (#527): in an integration
/// test, `enterText` does not go through the engine's text input plugin. It
/// hands the text to whichever text input connection the framework has open
/// *at that moment*, and drops it silently when none is open. And it asks for
/// the keyboard only the first time it types into a given field: the binding
/// remembers that field as `focusedEditable` and, with no mock text input
/// registered (as in every integration test), never forgets it. From the
/// second search on, typing relies entirely on the field still holding focus
/// from the tap.
///
/// It does not always. On a desktop the framework closes the field's
/// connection whenever the test window loses OS focus: the app goes
/// `inactive`, the [FocusManager] parks the primary focus on the root scope,
/// and gives it back only when the window is active again. A test window on a
/// live desktop loses focus now and then (a notification, another window, the
/// compositor settling a freshly mapped one), so typing once lost the text in
/// about one Linux run in ten. That is the harness typing into a window nobody
/// is looking at, not the app: a real user cannot type into an unfocused
/// window either, and the field gets its focus back with the window.
///
/// So this helper waits until the app is `resumed`, taps the field, forgets
/// the remembered `focusedEditable` so `enterText` asks for the keyboard again
/// right before it types, checks the field holds the text, and types again (up
/// to three tries) if the window was deactivated in that last instant.
Future<void> searchTutorials(WidgetTester tester, String query) async {
  final search = find.byKey(PatchTutorialBrowser.searchKey);
  String typed() => tester.widget<TextField>(search).controller!.text;
  for (var attempt = 0; attempt < 3 && typed() != query; attempt++) {
    await _untilWindowActive(tester);
    await tester.tap(search);
    await tester.pumpAndSettle();
    tester.binding.focusedEditable = null;
    await tester.enterText(search, query);
    await tester.pumpAndSettle();
  }
  expect(
    typed(),
    query,
    reason:
        'the Tutorials search field holds "$query" '
        '(app lifecycle: ${WidgetsBinding.instance.lifecycleState})',
  );
}

/// Waits, in real time, until the app is `resumed`: its window has OS focus,
/// so the field's text input connection stays open.
Future<void> _untilWindowActive(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
