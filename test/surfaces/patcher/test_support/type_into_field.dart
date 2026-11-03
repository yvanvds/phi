import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'until_window_active.dart';

/// **The** way a tutorial integration test types a value into a field on the
/// canvas, such as a number box, and commits it (issue #544).
///
/// Clicks the [TextField] that [field] finds, types [text] and presses
/// Enter, the way a user does. [what] names the field in failure messages.
///
/// Why this is more than `tap` + `enterText` + Enter: the same race as the
/// Tutorials search field ([searchTutorials], #527). `enterText` hands the
/// text to whichever text input connection is open at that moment, and on a
/// desktop the window going `inactive` parks the focus on the root scope,
/// which closes the field's connection. That happens whenever the test window
/// loses OS focus, which a window on a live desktop does: plain `xvfb-run`
/// in a Wayland session still opens the window on the real display (#544).
/// It can land between the click and the typing (the text is dropped), or
/// just after the typing (the field loses focus with the text in it).
///
/// A number box commits what was typed when it loses focus, so the two cases
/// must not be confused: typing again after the second one would send the
/// value twice. The helper therefore watches the field's controller for the
/// value `enterText` delivers (the text with the caret after it) and types
/// again (up to three tries, each after [untilWindowActive]) only while the
/// text has **not** reached the field. Once it has, it presses Enter if the
/// field still holds focus; if the field lost focus, the box has already
/// committed the value, exactly once, and Enter is not pressed.
Future<void> typeIntoField(
  WidgetTester tester,
  Finder field,
  String text, {
  required String what,
}) async {
  expect(field, findsOneWidget, reason: what);
  final textField = tester.widget<TextField>(field);
  final controller = textField.controller!;
  final focus = textField.focusNode!;
  // What `enterText` delivers: the text, with the caret after it. A click
  // selects a number box's whole value instead, so this tells typing apart
  // even when the box already showed [text] (typing the same seed twice).
  final typedValue = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  var typing = false;
  var landed = false;
  var blurred = false;
  void watchText() {
    if (typing &&
        controller.value.text == typedValue.text &&
        controller.value.selection == typedValue.selection) {
      landed = true;
    }
  }

  void watchFocus() {
    if (landed && !focus.hasFocus) blurred = true;
  }

  controller.addListener(watchText);
  focus.addListener(watchFocus);
  try {
    for (var attempt = 0; attempt < 3 && !landed; attempt++) {
      await untilWindowActive(tester);
      await tester.tap(field);
      await tester.pumpAndSettle();
      // enterText asks for the keyboard only the first time it types into a
      // field: forget the remembered one so it asks again right now (#527).
      tester.binding.focusedEditable = null;
      typing = true;
      await tester.enterText(field, text);
      typing = false;
    }
  } finally {
    controller.removeListener(watchText);
    focus.removeListener(watchFocus);
  }
  expect(
    landed,
    isTrue,
    reason:
        'typing "$text" reached $what '
        '(app lifecycle: ${WidgetsBinding.instance.lifecycleState})',
  );
  // Focused all along: Enter commits. Focus lost after the text landed (the
  // window went inactive): losing it committed the value already, and Enter
  // would send it again should the focus have come back since.
  if (focus.hasFocus && !blurred) {
    await tester.testTextInput.receiveAction(TextInputAction.done);
  }
  await tester.pumpAndSettle();
}
