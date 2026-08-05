import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_number_box.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.i` (int) and `.f` (float) number nodes — an editable readout
/// that pushes its value into the object's hot inlet via
/// [PatcherController.setControlValue] (`sendFloat`) on submit, then displays
/// the value the native side reports back through `guiValue` (design
/// `docs/design/patcher.md` §7).
///
/// The display is the engine's `guiValue`, re-read after each push, so a number
/// box shows the authoritative value rather than a Dart-side echo — the same
/// value a cable into its inlet would set. A [GuiValueLink] keeps it that way
/// between pushes too: a value arriving over a cable re-renders the box on its
/// own (issue #357), which is the whole point of a number box downstream of
/// anything. A box that **holds focus** is left alone — someone is typing in
/// it, and dropping the poll's value into a half-typed edit is the one thing a
/// refresh must never do.
///
/// Editing follows Max (issue #353): clicking the readout takes focus and
/// selects the whole value, so typing replaces it; **Enter** commits and pushes;
/// moving focus away commits whatever was typed; **Escape** throws the edit away
/// and snaps back to the live `guiValue`. The canvas leaves both the press and
/// the keys alone while this field holds focus, so Backspace edits text here
/// instead of deleting the selected nodes.
///
/// **Dragging** the readout up and down scrubs the value, Max-style (issue
/// #359) — the fast way to find a number, where typing is the exact one. Held
/// **Shift** scrubs finer. The two live side by side because the scrub is read
/// from a raw [Listener] rather than a recogniser: a press that never travels
/// past [_NumberNodeBodyState._scrubSlop] is left entirely to the field
/// underneath, so it still takes the caret and selects its value, while one
/// that does travel has already lost the field's own tap and belongs to the
/// scrub. Putting a drag recogniser here instead would have had to out-race the
/// [TextField]'s, which sits deeper and would win — the same arena problem
/// issue #352 took off the canvas.
///
/// Since issue #381 the node **is** the readout: no `NUMBER · F` header, no
/// frame, no padding around it — a [PatchNumberBox] fills the node's rectangle,
/// and its cut top-right corner is what tells a number box from a message box
/// now that no caption does. Presentation only: the push, the focus/commit/
/// revert behaviour, the `guiValue` link and the scrub are all untouched.
class NumberNodeBody extends StatefulWidget {
  const NumberNodeBody({
    required this.node,
    required this.controller,
    this.integer = false,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// `.i` rounds to a whole number; `.f` keeps the fractional value.
  final bool integer;

  @override
  State<NumberNodeBody> createState() => _NumberNodeBodyState();
}

class _NumberNodeBodyState extends State<NumberNodeBody> {
  late final GuiValueLink _gui;
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'number-node-field');

  /// Whether the user has typed since the last commit. Focus-loss commits only
  /// a dirty field, so merely clicking through a number box never re-pushes its
  /// own value back into the graph.
  bool _dirty = false;

  // ─── scrub state (issue #359) ──────────────────────────────────────────

  /// How far the pointer must travel vertically before a press becomes a scrub
  /// rather than a click. Wide enough that a click with a shaky hand still
  /// lands the caret, tight enough that the scrub feels immediate.
  static const double _scrubSlop = 4;

  /// Value units per pixel of drag. A float box sweeps whole units and refines
  /// to hundredths; an int box steps one per pixel and, held fine, one per ten.
  static const double _coarseStep = 1;
  static const double _fineFloatStep = 0.01;
  static const double _fineIntStep = 0.1;

  /// Whether a press is in flight over the readout at all (armed on down,
  /// dropped on up/cancel) — the gate that keeps stray moves from scrubbing.
  bool _scrubArmed = false;

  /// True from the moment the press clears [_scrubSlop] until it is released:
  /// the window in which the value belongs to the pointer and not to the
  /// engine, mirroring the fader's `_held`.
  bool _scrubbing = false;

  /// Pointer y and value the *current* leg of the scrub is measured from.
  /// Re-anchored when the scrub starts and whenever Shift is pressed or
  /// released mid-drag, so changing gear never makes the value jump.
  double _scrubAnchorY = 0;
  double _scrubStart = 0;
  bool _scrubFine = false;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _text = TextEditingController(text: _display());
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(NumberNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    // Detach first: disposing a focused node unfocuses it, and the listener
    // would otherwise commit into a half-torn-down widget.
    _focus.removeListener(_onFocusChange);
    _gui.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The engine reported a new value. A focused box is mid-edit and keeps what
  /// its owner typed, and one under a scrub belongs to the pointer; anything
  /// else re-renders, so a cable-driven number lands on the canvas without a
  /// click.
  void _follow(String raw) {
    if (_focus.hasFocus || _scrubbing) return;
    if (_text.text == _formatted(raw)) return;
    setState(_showLiveValue);
  }

  // ─── scrub (issue #359) ────────────────────────────────────────────────

  /// Arm a possible scrub. Nothing is claimed yet: a press that never travels
  /// is the [TextField]'s to answer, and it will place the caret as ever.
  void _onScrubDown(PointerDownEvent event) {
    _scrubArmed = true;
    _scrubbing = false;
    _scrubAnchorY = event.position.dy;
    _scrubStart = _liveValue();
  }

  /// Carry the value with the pointer. Up is more, matching every other
  /// vertical control in the app.
  void _onScrubMove(PointerMoveEvent event) {
    if (!_scrubArmed) return;
    final fine = HardwareKeyboard.instance.isShiftPressed;
    if (!_scrubbing) {
      if ((event.position.dy - _scrubAnchorY).abs() < _scrubSlop) return;
      _scrubbing = true;
      // Drop any half-typed edit *before* releasing the field, so leaving it
      // does not push a value the scrub is about to overwrite anyway.
      _dirty = false;
      _focus.unfocus();
      _reanchor(event.position.dy, fine);
    } else if (fine != _scrubFine) {
      // Changing gear mid-drag re-anchors rather than rescaling the whole
      // distance travelled so far — otherwise pressing Shift would fling the
      // value somewhere nobody asked for.
      _reanchor(event.position.dy, fine);
    }
    final travelled = event.position.dy - _scrubAnchorY;
    // The move that *starts* the scrub has travelled nothing since re-anchoring,
    // and a purely horizontal one never will: neither is a new value, and
    // pushing one would fire a redundant `sendFloat` into the graph.
    if (travelled == 0) return;
    final perPixel = fine
        ? (widget.integer ? _fineIntStep : _fineFloatStep)
        : _coarseStep;
    _push(_scrubStart - travelled * perPixel);
  }

  /// Hand the value back to the engine. Unlike the canvas's node drag — which
  /// deliberately *carries* its slop distance so the node never lags the
  /// pointer — the scrub re-anchors here, because spending the slop as value
  /// would make the number jump the moment it started moving.
  void _reanchor(double y, bool fine) {
    _scrubAnchorY = y;
    _scrubStart = _liveValue();
    _scrubFine = fine;
  }

  void _endScrub() {
    _scrubArmed = false;
    if (!_scrubbing) return;
    _scrubbing = false;
    // Re-read once on release, for the same reason the fader does: anything
    // that landed on the object while the pointer held it — a cable, a clamp
    // the object applied — would otherwise sit unreported until the next change.
    _showLiveValue();
  }

  /// The engine's current value for this object, as a number.
  double _liveValue() => double.tryParse(_gui.value) ?? 0;

  /// Send one scrubbed value and show what the engine makes of it.
  void _push(double raw) {
    widget.controller.setControlValue(
      widget.node.id,
      inlet: 0,
      value: widget.integer ? raw.roundToDouble() : raw,
    );
    _showLiveValue();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _selectAll();
    } else if (_dirty) {
      _commit(_text.text);
    }
  }

  /// The formatted live `guiValue`, or `0` before any value has been set.
  String _display() => _formatted(_gui.value);

  /// How a raw `guiValue` reads in the field. An unparseable value passes
  /// through untouched rather than being turned into a number it isn't.
  String _formatted(String gui) {
    final d = double.tryParse(gui);
    if (d == null) return gui.isEmpty ? '0' : gui;
    return _format(d);
  }

  String _format(double d) => widget.integer
      ? '${d.round()}'
      : (d == d.roundToDouble() ? '${d.toInt()}' : '$d');

  void _commit(String raw) {
    final d = double.tryParse(raw.trim());
    _dirty = false;
    if (d == null) {
      // Reject unparseable input: snap the field back to the live value.
      _showLiveValue();
      return;
    }
    widget.controller.setControlValue(
      widget.node.id,
      inlet: 0,
      value: widget.integer ? d.roundToDouble() : d,
    );
    // Re-read the authoritative display value the native side now reports.
    _showLiveValue();
  }

  /// Drop the edit and snap back to the engine's value, then hand the keyboard
  /// back so the canvas' own shortcuts work again.
  void _revert() {
    _dirty = false;
    _showLiveValue();
    _focus.unfocus();
  }

  /// Write the live `guiValue` into the field. While the box still holds focus
  /// the value stays selected, so the next keystroke replaces it — the same
  /// state a fresh click leaves it in.
  void _showLiveValue() {
    final text = _display();
    _text.value = TextEditingValue(
      text: text,
      selection: _focus.hasFocus
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length),
    );
  }

  void _selectAll() => _text.selection = TextSelection(
    baseOffset: 0,
    extentOffset: _text.text.length,
  );

  @override
  Widget build(BuildContext context) {
    // A raw [Listener], not a recogniser: it observes the pointer instead of
    // competing for it, so the field below keeps every press the scrub does
    // not claim (issue #359).
    return Listener(
      onPointerDown: _onScrubDown,
      onPointerMove: _onScrubMove,
      onPointerUp: (_) => _endScrub(),
      onPointerCancel: (_) => _endScrub(),
      child: PatchNumberBox(
        // Escape lives here rather than on the canvas: the canvas deliberately
        // ignores keys while a descendant holds focus (issue #353), and this
        // binding sits between the field and the canvas so it wins either way.
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revert},
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: (_) => _dirty = true,
            onSubmitted: _commit,
            // The readout's primary affordance is the drag, and the [TextField]
            // sits deeper than any region this body could wrap it in — so the
            // cursor is set on the field itself or it never shows at all.
            mouseCursor: SystemMouseCursors.resizeUpDown,
            // Drag-to-select-text is given up so drag-to-scrub can exist.
            // The two are the same gesture over the same three characters,
            // and the field's own one wins by construction: selecting on drag
            // reports `SelectionChangedCause.drag`, which asks for the
            // keyboard — so every scrub would end with the box back in edit
            // mode, deaf to the engine until it was clicked away from. A
            // click still focuses and still selects the whole value (issue
            // #353), which is the only selection a three-digit readout needs.
            enableInteractiveSelection: false,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            // Left, the way a Max number box reads — and the way the box's cut
            // right corner requires, since a right-aligned value would run into
            // it.
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            textAlign: TextAlign.left,
          ),
        ),
      ),
    );
  }
}
