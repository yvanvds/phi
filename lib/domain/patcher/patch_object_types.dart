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

  /// `Obj.gDial` — the knob, a 0–1 position mapped onto its own range
  /// (issue #470).
  static const String gDial = '.dial';

  /// `Obj.gIncdec` — the whole-number stepper (issue #470).
  static const String gIncdec = '.incdec';

  /// `Obj.gLed` — the labelled on/off lamp (issue #470).
  static const String gLed = '.led';

  /// `Obj.gTextbutton` — the labelled button; `.led`'s value model drawn as a
  /// button (issue #470).
  static const String gTextbutton = '.textbutton';

  /// `Obj.gTextedit` — the one-line editable text field (issue #470).
  static const String gTextedit = '.textedit';

  /// `Obj.gList` — the list box (issue #470).
  static const String gList = '.l';

  /// `Obj.gUmenu` — the drop-down menu over named items (issue #471).
  static const String gUmenu = '.umenu';

  /// `Obj.gRadiogroup` — `.umenu`'s value model drawn as a column of radio
  /// buttons, or check boxes with `multi` (issue #471).
  static const String gRadiogroup = '.radiogroup';

  /// `Obj.gTab` — `.umenu`'s value model drawn as a row of tabs (issue #471).
  static const String gTab = '.tab';

  /// `Obj.gRslider` — the range control, two ends inside its bounds
  /// (issue #472).
  static const String gRslider = '.rslider';

  /// `Obj.gXyslider` — the two-dimensional pad, an x and a y (issue #472).
  static const String gXyslider = '.xyslider';

  /// `Obj.gMultislider` — a bank of sliders, one cell each (issue #472).
  static const String gMultislider = '.multislider';

  /// `Obj.gKslider` — a piano keyboard, the velocity held on each of its 128
  /// keys (issue #473).
  static const String gKslider = '.kslider';

  /// `Obj.gNslider` — a note on a staff, its pitch and accidental
  /// (issue #473).
  static const String gNslider = '.nslider';

  /// `Obj.gMatrixctrl` — a grid of cells, columns by rows, each addressed as
  /// `<column> <row> <value>` (issue #474).
  static const String gMatrixctrl = '.matrixctrl';

  /// `Obj.gFunction` — a breakpoint function: sorted `<x> <y> <curve>`
  /// points, answered by x and banged out as a ramp (issue #475).
  static const String gFunction = '.function';

  /// `Obj.gNodes` — an interpolation field: circular `<x> <y> <radius>` nodes
  /// a cursor is weighed against, one weight per node out (issue #476).
  static const String gNodes = '.nodes';

  /// `Obj.gPreset` — a bank of numbered slots, each a snapshot of every
  /// settable control in the patch, stored and recalled (issue #477).
  static const String gPreset = '.preset';

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
    gDial,
    gIncdec,
    gLed,
    gTextbutton,
    gTextedit,
    gList,
    gUmenu,
    gRadiogroup,
    gTab,
    gRslider,
    gXyslider,
    gMultislider,
    gKslider,
    gNslider,
    gMatrixctrl,
    gFunction,
    gNodes,
    gPreset,
  ];
}
