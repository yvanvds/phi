/// FFI-free mirror of the engine object type ids the surfaces name directly
/// (issue #483).
///
/// The canonical list is `package:yse`'s `Obj.*` constants, but only
/// `lib/engine/bridge/` may import that package. The patcher surface needs a
/// handful of ids as plain strings — to register custom node bodies and to
/// seed the demo patch — so they are restated here in pure Dart. A drift
/// guard (`test/domain/patcher/patch_object_types_test.dart`) checks every id
/// against `Obj.all`, so a renamed engine object fails CI rather than silently
/// unregistering a node body.
///
/// Add an id here when a surface needs to name it; keep the field name equal
/// to the `Obj` constant it mirrors.
abstract final class PatchObjectTypes {
  /// `Obj.dSine` — the sine oscillator.
  static const String dSine = '~sine';

  /// `Obj.dDac` — the audio output.
  static const String dDac = '~dac';

  /// `Obj.gSlider` — the horizontal slider control.
  static const String gSlider = '.slider';

  /// `Obj.gToggle` — the on/off toggle control.
  static const String gToggle = '.t';

  /// `Obj.gButton` — the bang button control.
  static const String gButton = '.b';

  /// `Obj.gFloat` — the float number box.
  static const String gFloat = '.f';

  /// `Obj.gInt` — the integer number box.
  static const String gInt = '.i';

  /// `Obj.gMessage` — the message box.
  static const String gMessage = '.m';

  /// Every id above, for the drift guard.
  static const List<String> all = [
    dSine,
    dDac,
    gSlider,
    gToggle,
    gButton,
    gFloat,
    gInt,
    gMessage,
  ];
}
