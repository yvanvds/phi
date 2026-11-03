// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:ffi' as ffi;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/src/widgets/_window.dart';

import 'real_keyboard.dart';
import 'win32_keyboard_input.dart';

typedef _Hwnd = ffi.Pointer<ffi.Void>;

/// Real key presses on Windows, through `SendInput`: they join the system input
/// stream, so the focused window's message loop gets the `WM_KEYDOWN`, the
/// runner's `TranslateMessage` makes the `WM_CHAR`, and `KeyboardManager` and
/// `TextInputPlugin::TextHook` take it from there. `GetKeyState` sees the
/// modifiers too, which a posted `WM_KEYDOWN` would not.
///
/// Only the foreground window hears them, so [present] it first. The calls that
/// need the calling thread's input queue (`GetFocus`) rely on Dart running on
/// the platform thread, as the windowing API already does.
class Win32SendInputKeyboard implements RealKeyboard {
  Win32SendInputKeyboard() {
    final user32 = ffi.DynamicLibrary.open('user32.dll');
    final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    _sendInput = user32
        .lookupFunction<
          ffi.Uint32 Function(
            ffi.Uint32,
            ffi.Pointer<Win32KeyboardInput>,
            ffi.Int32,
          ),
          int Function(int, ffi.Pointer<Win32KeyboardInput>, int)
        >('SendInput');
    _vkKeyScan = user32
        .lookupFunction<ffi.Int16 Function(ffi.Uint16), int Function(int)>(
          'VkKeyScanW',
        );
    _mapVirtualKey = user32
        .lookupFunction<
          ffi.Uint32 Function(ffi.Uint32, ffi.Uint32),
          int Function(int, int)
        >('MapVirtualKeyW');
    _setForeground = user32
        .lookupFunction<ffi.Int32 Function(_Hwnd), int Function(_Hwnd)>(
          'SetForegroundWindow',
        );
    _getForeground = user32.lookupFunction<_Hwnd Function(), _Hwnd Function()>(
      'GetForegroundWindow',
    );
    _getFocus = user32.lookupFunction<_Hwnd Function(), _Hwnd Function()>(
      'GetFocus',
    );
    _isChild = user32
        .lookupFunction<
          ffi.Int32 Function(_Hwnd, _Hwnd),
          int Function(_Hwnd, _Hwnd)
        >('IsChild');
    _lastError = kernel32.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'GetLastError',
    );
    _topLevelWindow = ffi.DynamicLibrary.process()
        .lookupFunction<
          _Hwnd Function(ffi.Int64, ffi.Int64),
          _Hwnd Function(int, int)
        >('InternalFlutterWindows_WindowManager_GetTopLevelWindowHandle');
  }

  static const int _inputKeyboard = 1;
  static const int _extendedKey = 0x0001;
  static const int _keyUp = 0x0002;
  static const int _unicode = 0x0004;
  static const int _vkToScanCode = 0;

  static const int _vkReturn = 0x0D;
  static const int _vkShift = 0x10;
  static const int _vkControl = 0x11;
  static const int _vkDelete = 0x2E;

  /// `INPUT`'s size, which `SendInput` insists on.
  static final int _inputSize = ffi.sizeOf<Win32KeyboardInput>();

  late final int Function(int, ffi.Pointer<Win32KeyboardInput>, int) _sendInput;
  late final int Function(int) _vkKeyScan;
  late final int Function(int, int) _mapVirtualKey;
  late final int Function(_Hwnd) _setForeground;
  late final _Hwnd Function() _getForeground;
  late final _Hwnd Function() _getFocus;
  late final int Function(_Hwnd, _Hwnd) _isChild;
  late final int Function() _lastError;
  late final _Hwnd Function(int, int) _topLevelWindow;

  /// Sends [keys] as one uninterruptible batch.
  void _send(List<({int vk, int scan, int flags})> keys) {
    final inputs = calloc<Win32KeyboardInput>(keys.length);
    try {
      for (final (i, key) in keys.indexed) {
        inputs[i]
          ..type = _inputKeyboard
          ..virtualKey = key.vk
          ..scanCode = key.scan
          ..flags = key.flags;
      }
      final sent = _sendInput(keys.length, inputs, _inputSize);
      if (sent != keys.length) {
        throw StateError(
          'SendInput took $sent of ${keys.length} keys, error ${_lastError()}',
        );
      }
    } finally {
      calloc.free(inputs);
    }
  }

  ({int vk, int scan, int flags}) _key(
    int vk, {
    required bool down,
    bool extended = false,
  }) => (
    vk: vk,
    // The embedder reads the physical key from the scan code in the message.
    scan: _mapVirtualKey(vk, _vkToScanCode),
    flags: (down ? 0 : _keyUp) | (extended ? _extendedKey : 0),
  );

  void _tap(int vk, {int? modifier, bool extended = false}) => _send([
    if (modifier != null) _key(modifier, down: true),
    _key(vk, down: true, extended: extended),
    _key(vk, down: false, extended: extended),
    if (modifier != null) _key(modifier, down: false),
  ]);

  @override
  ffi.Pointer<ffi.Void> windowOf(
    FlutterView view,
    WindowController? controller,
  ) {
    final window = _topLevelWindow(
      PlatformDispatcher.instance.engineId!,
      view.viewId,
    );
    if (window == ffi.nullptr) {
      throw StateError('view ${view.viewId} has no window');
    }
    return window;
  }

  @override
  void present(ffi.Pointer<ffi.Void> window) => _setForeground(window);

  @override
  bool hasFocus(ffi.Pointer<ffi.Void> window) {
    final focus = _getFocus();
    return _getForeground() == window &&
        (focus == window || _isChild(window, focus) != 0);
  }

  @override
  String describeFocus(ffi.Pointer<ffi.Void> window) =>
      'window ${window.address}, foreground ${_getForeground().address}, '
      'focus ${_getFocus().address}, SetForegroundWindow says '
      '${_setForeground(window)}, error ${_lastError()}';

  @override
  void typeCharacter(int character) {
    final scan = _vkKeyScan(character);
    final vk = scan & 0xFF;
    final shiftState = (scan >> 8) & 0xFF;
    if (scan == -1 || shiftState > 1) {
      // Not a key press on this layout, or AltGr and maybe a dead key (`~` on
      // many European ones): a packet, as an input method sends. It reaches the
      // same message loop and TextHook, without a key event.
      _send([
        (vk: 0, scan: character, flags: _unicode),
        (vk: 0, scan: character, flags: _unicode | _keyUp),
      ]);
      return;
    }
    _tap(vk, modifier: shiftState == 1 ? _vkShift : null);
  }

  @override
  void enter() => _tap(_vkReturn);

  @override
  void delete() => _tap(_vkDelete, extended: true);

  @override
  void control(String letter) =>
      _tap(letter.toUpperCase().codeUnitAt(0), modifier: _vkControl);
}
