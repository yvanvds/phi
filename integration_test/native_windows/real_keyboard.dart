// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:ffi' as ffi;
import 'dart:ui';

import 'package:flutter/src/widgets/_window.dart';

/// Key presses the operating system makes, with the same effect as a physical
/// keyboard: they go to the window holding the keyboard focus, and from there
/// through the engine's keyboard manager and text input plugin. Nothing in the
/// framework or on a channel is stood in for.
abstract interface class RealKeyboard {
  /// The native top-level window showing [view]: its [controller], or the main
  /// window when that is null. For the main window, call this after its first
  /// frame, and before opening any other.
  ffi.Pointer<ffi.Void> windowOf(
    FlutterView view,
    WindowController? controller,
  );

  /// Raises [window] and asks for the keyboard focus. The answer may come later,
  /// so check [hasFocus].
  void present(ffi.Pointer<ffi.Void> window);

  /// Whether [window] holds the keyboard focus.
  bool hasFocus(ffi.Pointer<ffi.Void> window);

  /// What the platform says about the focus and [window], for a failure message.
  String describeFocus(ffi.Pointer<ffi.Void> window);

  /// Presses the keys that make the printable ASCII [character].
  void typeCharacter(int character);

  /// Presses and releases Enter.
  void enter();

  /// Presses and releases Delete.
  void delete();

  /// Presses and releases the ASCII letter key [letter] with Ctrl held.
  void control(String letter);
}
