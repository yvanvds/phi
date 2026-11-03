// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'linux_x_test_keyboard.dart';
import 'text_input_view_rule_check.dart';

/// The keyboard of a test on real native windows, as close to the platform as
/// each OS allows.
///
/// - **Linux:** real key presses ([LinuxXTestKeyboard]). Text reaches a field
///   only through the engine's keyboard manager and text input plugin, and goes
///   to the window that holds the X focus.
/// - **Elsewhere:** the plugin still hears every call from the field, but nothing
///   types: the editing state it would report is delivered on the text input
///   channel, and keys are simulated in the framework. Real Win32 input is #558.
class NativeKeyboard {
  NativeKeyboard(this._tester, this._textInput)
    : _x = Platform.isLinux ? LinuxXTestKeyboard() : null;

  /// How long, in real time, a key press may take to land.
  static const Duration _landing = Duration(seconds: 5);

  final WidgetTester _tester;
  final TextInputViewRuleCheck _textInput;
  final LinuxXTestKeyboard? _x;
  ffi.Pointer<ffi.Void>? _mainWindow;

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
    final window = isMain ? null : _windowOf(view);
    final x = _x;
    if (x == null) {
      window?.activate();
      await _tester.pump();
      return;
    }
    final handle = isMain
        ? _mainWindow ??= x.onlyVisibleWindow()
        : (window! as WindowControllerLinux).windowHandle;
    final waited = Stopwatch()..start();
    x.present(handle);
    while (!x.isActive(handle)) {
      if (waited.elapsed > _landing) {
        throw StateError('view ${view.viewId} never got the X focus');
      }
      await _breathe();
      x.present(handle);
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
    final x = _x;
    if (x == null) {
      _textInput.deliver(text);
    } else if (text.startsWith(shown())) {
      text.substring(shown().length).codeUnits.forEach(x.typeCharacter);
    }
    await _until(() => shown() == text);
  }

  /// Presses Enter, and waits for [until], or [_landing]: the caller checks.
  Future<void> enter({required bool Function() until}) => _press(
    LogicalKeyboardKey.enter,
    keysym: LinuxXTestKeyboard.returnKey,
    until: until,
  );

  /// Presses Delete, and waits for [until], or [_landing]: the caller checks.
  Future<void> delete({required bool Function() until}) => _press(
    LogicalKeyboardKey.delete,
    keysym: LinuxXTestKeyboard.deleteKey,
    until: until,
  );

  /// Presses Ctrl and the letter [key], and waits for [until], or [_landing]:
  /// the caller checks.
  Future<void> control(
    LogicalKeyboardKey key, {
    required bool Function() until,
  }) async {
    final x = _x;
    if (x == null) {
      await _tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _tester.sendKeyEvent(key);
      await _tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    } else {
      x.tap(
        key.keyLabel.toLowerCase().codeUnitAt(0),
        modifier: LinuxXTestKeyboard.controlLeft,
      );
    }
    await _until(until);
  }

  Future<void> _press(
    LogicalKeyboardKey key, {
    required int keysym,
    required bool Function() until,
  }) async {
    final x = _x;
    if (x == null) {
      await _tester.sendKeyEvent(key);
    } else {
      x.tap(keysym);
    }
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
