import 'dart:ffi' as ffi;
import 'dart:io';

typedef _Pointer = ffi.Pointer<ffi.Void>;

/// Real key presses on the X server (Linux only), through the XTEST extension
/// Xvfb has — the same events a physical keyboard produces, so they reach the
/// focused GTK window, `FlKeyboardManager` and the engine's text input plugin
/// (`GtkIMContext`).
///
/// Xvfb runs no window manager, so X focus does not follow anything: move it
/// with [present] first.
class LinuxXTestKeyboard {
  LinuxXTestKeyboard() {
    if (Platform.environment['WAYLAND_DISPLAY'] != null) {
      throw StateError(
        'XTEST needs the X11 backend. Run integration tests the way CLAUDE.md '
        'says, with WAYLAND_DISPLAY unset and GDK_BACKEND=x11.',
      );
    }
    final x11 = ffi.DynamicLibrary.open('libX11.so.6');
    final xtst = ffi.DynamicLibrary.open('libXtst.so.6');
    final process = ffi.DynamicLibrary.process();
    _display = process
        .lookupFunction<_Pointer Function(), _Pointer Function()>(
          'gdk_x11_get_default_xdisplay',
        )
        .call();
    _keycodeOf = x11
        .lookupFunction<
          ffi.Uint8 Function(_Pointer, ffi.UnsignedLong),
          int Function(_Pointer, int)
        >('XKeysymToKeycode');
    _keysymAt = x11
        .lookupFunction<
          ffi.UnsignedLong Function(_Pointer, ffi.Uint8, ffi.Int32, ffi.Int32),
          int Function(_Pointer, int, int, int)
        >('XkbKeycodeToKeysym');
    _fakeKey = xtst
        .lookupFunction<
          ffi.Int32 Function(
            _Pointer,
            ffi.UnsignedInt,
            ffi.Int32,
            ffi.UnsignedLong,
          ),
          int Function(_Pointer, int, int, int)
        >('XTestFakeKeyEvent');
    _flush = x11
        .lookupFunction<ffi.Int32 Function(_Pointer), int Function(_Pointer)>(
          'XFlush',
        );
    _listToplevels = process
        .lookupFunction<
          ffi.Pointer<ffi.Pointer<ffi.Void>> Function(),
          ffi.Pointer<ffi.Pointer<ffi.Void>> Function()
        >('gtk_window_list_toplevels');
    _isVisible = process
        .lookupFunction<ffi.Int32 Function(_Pointer), int Function(_Pointer)>(
          'gtk_widget_get_visible',
        );
    _isActive = process
        .lookupFunction<ffi.Int32 Function(_Pointer), int Function(_Pointer)>(
          'gtk_window_is_active',
        );
    _present = process
        .lookupFunction<ffi.Void Function(_Pointer), void Function(_Pointer)>(
          'gtk_window_present',
        );
    _freeList = process
        .lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Pointer<ffi.Void>>),
          void Function(ffi.Pointer<ffi.Pointer<ffi.Void>>)
        >('g_list_free');
  }

  /// X keysyms of the keys that are not characters.
  static const int returnKey = 0xFF0D;
  static const int deleteKey = 0xFFFF;
  static const int controlLeft = 0xFFE3;
  static const int shiftLeft = 0xFFE1;

  late final _Pointer _display;
  late final int Function(_Pointer, int) _keycodeOf;
  late final int Function(_Pointer, int, int, int) _keysymAt;
  late final int Function(_Pointer, int, int, int) _fakeKey;
  late final int Function(_Pointer) _flush;
  late final ffi.Pointer<ffi.Pointer<ffi.Void>> Function() _listToplevels;
  late final int Function(_Pointer) _isVisible;
  late final int Function(_Pointer) _isActive;
  late final void Function(_Pointer) _present;
  late final void Function(ffi.Pointer<ffi.Pointer<ffi.Void>>) _freeList;

  int _keycode(int keysym) {
    final keycode = _keycodeOf(_display, keysym);
    if (keycode == 0) {
      throw ArgumentError.value(keysym, 'keysym', 'not on the X keyboard map');
    }
    return keycode;
  }

  void _send(int keycode, {required bool down}) {
    _fakeKey(_display, keycode, down ? 1 : 0, 0);
  }

  /// Presses and releases the key of [keysym], with [modifier] (a keysym) held
  /// around it.
  void tap(int keysym, {int? modifier}) {
    final keycode = _keycode(keysym);
    final held = modifier == null ? null : _keycode(modifier);
    if (held != null) _send(held, down: true);
    _send(keycode, down: true);
    _send(keycode, down: false);
    if (held != null) _send(held, down: false);
    _flush(_display);
  }

  /// Presses the keys that make the ASCII [character], with Shift when the
  /// keyboard map has it on the shifted level. A printable ASCII character's
  /// keysym is its code unit.
  void typeCharacter(int character) {
    final keycode = _keycode(character);
    final shifted = _keysymAt(_display, keycode, 0, 0) != character;
    tap(character, modifier: shifted ? shiftLeft : null);
  }

  /// The main window: the one toplevel showing while no other window is open.
  /// Call after the main window's first frame (it shows then), and before
  /// opening any other.
  ffi.Pointer<ffi.Void> onlyVisibleWindow() {
    final list = _listToplevels();
    final visible = <_Pointer>[];
    for (var node = list; node != ffi.nullptr; node = node[1].cast()) {
      if (_isVisible(node[0]) != 0) visible.add(node[0]);
    }
    _freeList(list);
    if (visible.length != 1) {
      throw StateError('expected one visible window, found ${visible.length}');
    }
    return visible.single;
  }

  /// Raises [gtkWindow] and moves the X focus to it.
  void present(ffi.Pointer<ffi.Void> gtkWindow) => _present(gtkWindow);

  /// Whether [gtkWindow] holds the X focus.
  bool isActive(ffi.Pointer<ffi.Void> gtkWindow) => _isActive(gtkWindow) != 0;
}
