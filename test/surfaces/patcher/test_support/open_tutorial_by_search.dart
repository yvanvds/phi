import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_browser.dart';

import 'until_window_active.dart';

/// **The** way a tutorial integration test opens a tutorial (issue #527).
///
/// Types [type] into the Tutorials browser's search field
/// ([PatchTutorialBrowser.searchKey]), checks the field really holds it, then
/// taps the type's entry and settles. The browser is a `ListView` that builds
/// only the entries near its viewport (#524), so the helper searches first,
/// which narrows the list, and scrolls to the entry when the search still
/// leaves more rows than fit (#541). The palette's Tutorials tab must already
/// be showing. What the opened tutorial looks like is left to the
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
///
/// Searching narrows the list, but a short query can still match more entries
/// than fit: `.s` also matches every type or description containing `.s`
/// (`.seq`, `.sel`, …), and the browser builds only the rows near its
/// viewport. So when the entry is not built yet, the helper scrolls the
/// browser down until it is (#541), and fails naming the rows it did see.
Future<void> openTutorialBySearch(WidgetTester tester, String type) async {
  await searchTutorials(tester, type);
  final entry = find.byKey(PatchTutorialBrowser.entryKey(type));
  await _scrollToEntry(tester, entry, type);
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

/// Scrolls the Tutorials browser's list down a row-ish step at a time until
/// [entry] is built, or the list ends.
Future<void> _scrollToEntry(
  WidgetTester tester,
  Finder entry,
  String type,
) async {
  // The list scrolls down; the search field's own Scrollable runs across.
  final list = find.descendant(
    of: find.byType(PatchTutorialBrowser),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  final seen = <String>{};
  for (var step = 0; step < 200 && entry.evaluate().isEmpty; step++) {
    seen.addAll(_builtEntries());
    if (list.evaluate().isEmpty) break;
    final position = tester.state<ScrollableState>(list.first).position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 96).clamp(0.0, position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  seen.addAll(_builtEntries());
  expect(
    entry,
    findsOneWidget,
    reason:
        'the Tutorials browser lists $type after searching for it; '
        'rows seen while scrolling: ${(seen.toList()..sort()).join(' ')}',
  );
}

/// The types whose rows the browser has built right now.
Iterable<String> _builtEntries() sync* {
  const prefix = 'PatchTutorialBrowser.entry.';
  for (final e in find.byType(GestureDetector).evaluate()) {
    final key = e.widget.key;
    if (key is ValueKey<String> && key.value.startsWith(prefix)) {
      yield key.value.substring(prefix.length);
    }
  }
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
/// So this helper gives an inactive window a moment to come back (see
/// [untilWindowActive]), taps the field, forgets the remembered
/// `focusedEditable` so `enterText` asks for the keyboard again right before
/// it types, checks the field holds the text, and types again (up to three
/// tries) if the window was deactivated in that last instant.
///
/// What loses the text is the window going inactive *between* the tap and
/// the typing. A window that is already inactive and stays so is fine: the
/// tap focuses the field and `enterText` opens its connection. Under
/// `xvfb-run` (no window manager) the window can go inactive once a tutorial
/// opens and never come back (#542), so the helper must not wait for
/// `resumed` for long.
Future<void> searchTutorials(WidgetTester tester, String query) async {
  final search = find.byKey(PatchTutorialBrowser.searchKey);
  String typed() => tester.widget<TextField>(search).controller!.text;
  for (var attempt = 0; attempt < 3 && typed() != query; attempt++) {
    await untilWindowActive(tester);
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
