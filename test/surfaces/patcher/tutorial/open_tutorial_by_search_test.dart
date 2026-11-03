import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_browser.dart';

import '../test_support/open_tutorial_by_search.dart';

/// Pins the cause of the intermittent tutorial integration test failure
/// (issue #527) and the shared helper that fixes it.
///
/// On a desktop the [FocusManager] parks the primary focus on the root scope
/// while the window is inactive, which closes the search field's text input
/// connection. `enterText` then goes nowhere. These tests deactivate the app
/// between the tap and the typing, the way the OS does when the test window
/// loses focus on a live desktop.
void main() {
  PatchObjectDescriptor object(String type) => PatchObjectDescriptor(
    type: type,
    description: 'the $type object',
    category: PatchObjectCategory.math,
    isDsp: false,
    inlets: const [],
    outlets: const [],
    params: const [],
  );

  final opened = <String>[];

  // Text input the way an integration test has it: no mock text input
  // plugin, so `enterText` hands the text to whatever connection is open
  // (none, after the field lost focus), and the binding never forgets which
  // field it last typed into.
  void asInIntegrationTest(WidgetTester tester) {
    tester.testTextInput.unregister();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (_) async => null,
    );
    addTearDown(tester.testTextInput.register);
  }

  Future<void> pumpBrowser(WidgetTester tester) async {
    opened.clear();
    asInIntegrationTest(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchTutorialBrowser(
            objectTypes: [object('.+'), object('.-')],
            tutorialTypes: const {'.+', '.-'},
            onOpen: opened.add,
          ),
        ),
      ),
    );
    // Make the field the binding's focused editable now, as the first search
    // of an integration test does: from then on `enterText` no longer asks
    // for the keyboard itself, so typing relies on the tap alone.
    await tester.enterText(find.byKey(PatchTutorialBrowser.searchKey), 'x');
    await tester.pumpAndSettle();
  }

  void setLifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  String typed(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(PatchTutorialBrowser.searchKey))
      .controller!
      .text;

  testWidgets(
    'the cause: text typed while the window is inactive never reaches the '
    'search field',
    (tester) async {
      addTearDown(() => setLifecycle(tester, AppLifecycleState.resumed));
      await pumpBrowser(tester);
      final search = find.byKey(PatchTutorialBrowser.searchKey);
      await tester.tap(search);
      await tester.pumpAndSettle();
      setLifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      await tester.enterText(search, '.-');
      await tester.pumpAndSettle();
      expect(typed(tester), 'x', reason: 'the connection was closed');
      // The field gets its focus back with the window: a user who comes back
      // to the window types into it straight away.
      setLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(search, '.-');
      await tester.pumpAndSettle();
      expect(typed(tester), '.-');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('openTutorialBySearch still types the text when the window is '
      'deactivated right after the tap', (tester) async {
    addTearDown(() => setLifecycle(tester, AppLifecycleState.resumed));
    await pumpBrowser(tester);
    // The field lost focus since the last search, as when an entry was
    // tapped and its tutorial opened.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final field = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    // The OS takes the window's focus the moment the tap lands.
    var deactivated = false;
    void deactivate() {
      if (field.hasFocus && !deactivated) {
        deactivated = true;
        scheduleMicrotask(
          () => setLifecycle(tester, AppLifecycleState.inactive),
        );
      }
    }

    field.addListener(deactivate);
    addTearDown(() => field.removeListener(deactivate));
    await openTutorialBySearch(tester, '.-');
    expect(deactivated, isTrue);
    expect(typed(tester), '.-');
    expect(opened, ['.-']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'openTutorialBySearch waits for an inactive window to come back',
    (tester) async {
      addTearDown(() => setLifecycle(tester, AppLifecycleState.resumed));
      await pumpBrowser(tester);
      setLifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      var resumed = false;
      // The window comes back a little later, in real time.
      await tester.runAsync(() async {
        Timer(const Duration(milliseconds: 200), () {
          resumed = true;
          setLifecycle(tester, AppLifecycleState.resumed);
        });
      });
      await openTutorialBySearch(tester, '.-');
      expect(resumed, isTrue, reason: 'typed only once the window was back');
      expect(typed(tester), '.-');
      expect(opened, ['.-']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'openTutorialBySearch types into a window that stays inactive without '
    'waiting long for it (#542)',
    (tester) async {
      // Under xvfb-run, with no window manager, the window can go inactive
      // once a tutorial opens and never come back. Typing still works then:
      // the tap focuses the field and enterText opens its connection.
      addTearDown(() => setLifecycle(tester, AppLifecycleState.resumed));
      await pumpBrowser(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      setLifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      final took = Stopwatch()..start();
      await openTutorialBySearch(tester, '.-');
      took.stop();
      expect(typed(tester), '.-');
      expect(opened, ['.-']);
      expect(
        took.elapsed,
        lessThan(const Duration(seconds: 4)),
        reason: 'gave up waiting for a window that never comes back',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('openTutorialBySearch scrolls to an entry the search leaves '
      'below the fold (#541)', (tester) async {
    // `.s` also matches `.seq`, `.sel` and every description with `.s` in
    // it, which here sort before it: more rows than the browser shows.
    final types = [for (var i = 0; i < 60; i++) '.s${'x' * (i + 1)}'];
    final all = [...types.map(object), object('.s')];
    opened.clear();
    asInIntegrationTest(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: PatchTutorialBrowser(
              objectTypes: all,
              tutorialTypes: {for (final d in all) d.type},
              onOpen: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTutorialBySearch(tester, '.s');
    expect(opened, ['.s']);
  });
}
