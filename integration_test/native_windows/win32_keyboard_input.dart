import 'dart:ffi' as ffi;

/// The 64-bit Win32 `INPUT` struct with its `KEYBDINPUT` arm: `SendInput`
/// rejects anything whose size is not 40, the size of the union's largest arm
/// (`MOUSEINPUT`) plus the type and its padding.
final class Win32KeyboardInput extends ffi.Struct {
  @ffi.Uint32()
  external int type;

  @ffi.Uint32()
  external int alignsTheUnion;

  @ffi.Uint16()
  external int virtualKey;

  @ffi.Uint16()
  external int scanCode;

  @ffi.Uint32()
  external int flags;

  @ffi.Uint32()
  external int time;

  @ffi.UintPtr()
  external int extraInfo;

  @ffi.Uint64()
  external int restOfTheUnion;
}
