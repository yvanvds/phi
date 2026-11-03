// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'linux_x_test_keyboard.dart';
import 'real_keyboard.dart';
import 'text_input_view_rule_check.dart';
import 'win32_send_input_keyboard.dart';

/// The keyboard of a test on real native windows: real key presses, from
/// [LinuxXTestKeyboard] or [Win32SendInputKeyboard]. Text reaches a field only
/// through the engine's keyboard manager and text input plugin, and goes to the
/// window that holds the keyboard focus.
class NativeKeyboard {
  NativeKeyboard(this._tester, this._textInput)
    : _keys = Platform.isWindows
          ? Win32SendInputKeyboard()
          : LinuxXTestKeyboard();

  /// How long, in real time, a key press may take to land.
  static const Duration _landing = Duration(seconds: 5);

  final WidgetTester _tester;
  final TextInputViewRuleCheck _textInput;
  final RealKeyboard _keys;

  /// Lets real time pass, so the platform loop runs, and pumps what it did.
  Future<void> _breathe() async {
    await _tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await _tester.pump();
  }

  /// Hands the keyboard to the window showing [view], as a click on it does on
  /// a desktop.
  Future<void> focus(FlutterView view) async {
    final isMain =
        view.viewId == PlatformDispatcher.instance.implicitView?.viewId;
    final window = _keys.windowOf(view, isMain ? null : _windowOf(view));
    final waited = Stopwatch()..start();
    _keys.present(window);
    while (!_keys.hasFocus(window)) {
      if (waited.elapsed > _landing) {
        throw StateError(
          'view ${view.viewId} never got the keyboard focus: '
          '${_keys.describeFocus(window)}',
        );
      }
      await _breathe();
      _keys.present(window);
    }
    await _breathe();
  }

  WindowController _windowOf(FlutterView view) => _tester
      .widgetList<Window>(find.byType(Window))
      .singleWhere((w) => w.controller.rootView.viewId == view.viewId)
      .controller;

  /// The text [field] shows.
  String textIn(Finder field) => _tester
      .state<EditableTextState>(
        find.descendant(
          of: field,
          matching: find.byType(EditableText),
          matchRoot: true,
        ),
      )
      .textEditingValue
      .text;

  /// Types [text] into [field], which holds the keyboard, and returns once it
  /// shows all of it, or after [_landing] if it never does: the caller checks.
  /// What the field already shows of [text] is not typed again.
  Future<void> type(Finder field, String text) async {
    String shown() => textIn(field);
    await _until(() => _textInput.clientId != null);
    if (text.startsWith(shown())) {
      text.substring(shown().length).codeUnits.forEach(_keys.typeCharacter);
    }
    await _until(() => shown() == text);
  }

  /// Presses Enter, and waits for [until], or [_landing]: the caller checks.
  Future<void> enter({required bool Function() until}) async {
    _keys.enter();
    await _until(until);
  }

  /// Presses Delete, and waits for [until], or [_landing]: the caller checks.
  Future<void> delete({required bool Function() until}) async {
    _keys.delete();
    await _until(until);
  }

  /// Presses Ctrl and the letter [key], and waits for [until], or [_landing]:
  /// the caller checks.
  Future<void> control(
    LogicalKeyboardKey key, {
    required bool Function() until,
  }) async {
    _keys.control(key.keyLabel);
    await _until(until);
  }

  /// A key press has no answer to wait for, only what it does.
  Future<void> _until(bool Function() landed) async {
    final waited = Stopwatch()..start();
    while (!landed() && waited.elapsed < _landing) {
      await _breathe();
    }
    await _tester.pumpAndSettle();
  }
}
