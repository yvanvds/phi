import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../engine/bridge/patch_creation_args.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';

/// The **inline object box** — the Max speed path for making an object: a
/// double-click on empty canvas drops this empty box at the click point, the
/// name is typed with completion, and Enter instantiates (issue #358).
///
/// The palette stays the discovery route; this is the one where the hands never
/// leave the keyboard, so every decision below is made in favour of not making
/// the user reach for the mouse:
/// - **Completion narrows on every keystroke** over the same catalogue the
///   palette renders (`PatcherController.objectTypes`), matching a typed name
///   against the type id *and* its one-line description. Prefix matches sort
///   ahead of substring ones, so `sine` offers `~sine` first.
/// - **Arrows move the highlight, Tab inserts it** into the field (leaving a
///   trailing space, since arguments come next), and **Enter instantiates** —
///   using the typed name when it is already an exact type, and the highlighted
///   completion when it isn't. So `sine 220` + Enter makes a `~sine 220` without
///   ever pressing Tab.
/// - **Anything after the first token is the argument string**, checked against
///   the type's documented [PatchParamDescriptor]s ([PatchCreationArgs]) before
///   anything is created — the engine crashes on arguments an object never
///   declared, and an out-of-range value silently misconfigures it.
/// - **A refusal keeps the box open** with the reason under it, so a typo is
///   corrected in place rather than costing the whole gesture. **Escape**
///   dismisses and leaves the canvas exactly as it was.
///
/// Keys are owned *here* rather than on the canvas: the canvas deliberately
/// ignores every key while a descendant holds focus (issue #353), so — exactly
/// like the number box — the bindings sit between this field and the canvas,
/// where they beat both the canvas's shortcuts and Flutter's own text-editing
/// and traversal defaults.
class PatchInlineObjectBox extends StatefulWidget {
  const PatchInlineObjectBox({
    required this.objectTypes,
    required this.onCreate,
    required this.onDismiss,
    super.key,
  });

  /// The catalogue to complete against — the palette's own source.
  final List<PatchObjectDescriptor> objectTypes;

  /// Called when Enter resolved a type and its arguments passed the check.
  final void Function(PatchObjectDescriptor desc, String args) onCreate;

  /// Called when the box gives up the gesture (Escape). The canvas is left
  /// untouched.
  final VoidCallback onDismiss;

  /// Width of the typing field. The completion list matches it.
  static const double width = 190;

  /// Key on the type-in field.
  static const Key fieldKey = Key('PatchInlineObjectBox.field');

  /// Key on the inline reject line — present only while a refusal stands, so
  /// its absence is assertable.
  static const Key rejectKey = Key('PatchInlineObjectBox.reject');

  /// Key on one completion row, by the type it offers.
  static Key rowKey(String type) => Key('PatchInlineObjectBox.row.$type');

  @override
  State<PatchInlineObjectBox> createState() => _PatchInlineObjectBoxState();
}

class _PatchInlineObjectBoxState extends State<PatchInlineObjectBox> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'patch-inline-object');
  final ScrollController _scroll = ScrollController();

  /// Catalogue entries matching the name typed so far, best first.
  List<PatchObjectDescriptor> _matches = const [];

  /// Index into [_matches] the arrows move and Tab/Enter take.
  int _index = 0;

  /// Why the last Enter was refused, or null. Cleared by the next keystroke, so
  /// the box never argues with what is now on screen.
  String? _reject;

  /// Whether an Enter has already been honoured. Enter arrives twice on a
  /// desktop text field — once as a key event this widget's own binding claims,
  /// once as the platform's submit action — and creating the object twice off
  /// one keypress is not a mistake the undo stack should have to describe.
  bool _created = false;

  static const double _rowHeight = 24;
  static const double _maxListHeight = 168;

  @override
  void initState() {
    super.initState();
    _matches = _matchesFor('');
    // Take the keyboard *explicitly* rather than with `autofocus`. The canvas
    // grabs focus on the very pointer-up that opens this box, and an autofocus
    // is skipped whenever its scope already has a focused descendant — so the
    // box would come up with the canvas still holding the keys and the first
    // letters of the name would run canvas shortcuts (`d` duplicates, Delete
    // deletes) instead of being typed. Requesting it here, once the node is
    // attached, is unconditional: the box always opens ready to type into,
    // whoever had the keyboard a moment earlier.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The name token — everything before the first whitespace.
  String get _name {
    final raw = _text.text.trimLeft();
    final cut = raw.indexOf(RegExp(r'\s'));
    return cut < 0 ? raw : raw.substring(0, cut);
  }

  /// The argument text — everything after the first whitespace.
  String get _typedArgs {
    final raw = _text.text.trimLeft();
    final cut = raw.indexOf(RegExp(r'\s'));
    return cut < 0 ? '' : raw.substring(cut + 1);
  }

  /// Catalogue entries for a typed [name], prefix matches first.
  ///
  /// A `~`/`.` prefix is part of the type id but not of how anyone says the
  /// name, so `sine` has to reach `~sine`: a match on the id *without* its
  /// prefix ranks as a prefix match, ahead of a plain substring hit and well
  /// ahead of a description-only one.
  List<PatchObjectDescriptor> _matchesFor(String name) {
    if (name.isEmpty) return List.of(widget.objectTypes);
    final q = name.toLowerCase();
    final ranked = <(int, PatchObjectDescriptor)>[];
    for (final d in widget.objectTypes) {
      final type = d.type.toLowerCase();
      final bare = _bare(type);
      if (type == q || bare == q) {
        ranked.add((0, d));
      } else if (type.startsWith(q) || bare.startsWith(q)) {
        ranked.add((1, d));
      } else if (type.contains(q)) {
        ranked.add((2, d));
      } else if (d.description.toLowerCase().contains(q)) {
        ranked.add((3, d));
      }
    }
    ranked.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final r in ranked) r.$2];
  }

  /// A type id without its `~` (DSP) or `.` (control) prefix.
  static String _bare(String type) =>
      type.startsWith('~') || type.startsWith('.') ? type.substring(1) : type;

  void _onChanged(String _) {
    setState(() {
      _matches = _matchesFor(_name);
      _index = 0;
      _reject = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _index = (_index + delta) % _matches.length;
      if (_index < 0) _index += _matches.length;
    });
    _revealSelected();
  }

  /// Scroll the highlighted row into view, so arrowing past the bottom of a
  /// long catalogue keeps showing what is selected — a completion the eye
  /// cannot follow is worse than none.
  void _revealSelected() {
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    final max = _scroll.position.maxScrollExtent;
    final top = _index * _rowHeight;
    final bottom = top + _rowHeight;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top.clamp(0.0, max));
    } else if (bottom > _scroll.offset + view) {
      _scroll.jumpTo((bottom - view).clamp(0.0, max));
    }
  }

  /// The type the current text would instantiate: an exact catalogue id when the
  /// name already is one, else whatever the highlight is on.
  PatchObjectDescriptor? get _resolved {
    final name = _name;
    if (name.isEmpty) return null;
    for (final d in widget.objectTypes) {
      if (d.type == name) return d;
    }
    if (_matches.isEmpty) return null;
    return _matches[_index.clamp(0, _matches.length - 1)];
  }

  /// Tab: write the highlighted type into the field, leaving the caret past a
  /// trailing space so arguments can be typed straight on.
  void _insertCompletion() {
    final desc = _resolved;
    if (desc == null) return;
    final args = _typedArgs;
    final text = args.isEmpty ? '${desc.type} ' : '${desc.type} $args';
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _matches = _matchesFor(desc.type);
      _index = 0;
      _reject = null;
    });
  }

  /// Enter: resolve the name, check the arguments, and create — or refuse
  /// inline and stay open.
  void _submit() {
    if (_created) return;
    if (_name.isEmpty) {
      setState(() => _reject = 'type an object name');
      return;
    }
    final desc = _resolved;
    if (desc == null) {
      setState(() => _reject = 'unknown object · $_name');
      return;
    }
    final checked = PatchCreationArgs.check(desc, _typedArgs);
    final problem = checked.problem;
    if (problem != null) {
      setState(() => _reject = problem);
      return;
    }
    _created = true;
    widget.onCreate(desc, checked.args);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Bound here, between the field and the canvas, so they beat *both* the
      // canvas's own shortcuts and Flutter's text-editing and Tab-traversal
      // defaults — the placement the number box's Escape already relies on.
      // Enter is bound as well as handled through `onSubmitted`: the submit
      // action is a platform round-trip that a test (and a headless run) never
      // makes, and this is the gesture's whole point.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.tab): _insertCompletion,
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(),
          if (_reject != null) _rejectLine(_reject!),
          if (_matches.isNotEmpty) _completions(),
        ],
      ),
    );
  }

  Widget _field() {
    return Container(
      width: PatchInlineObjectBox.width,
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all1,
        border: Border.all(
          color: _reject != null ? PhiColors.hot : PhiColors.voice1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
      child: TextField(
        key: PatchInlineObjectBox.fieldKey,
        controller: _text,
        focusNode: _focus,
        onChanged: _onChanged,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: PhiSpacing.s2),
          hintText: 'object…',
          hintStyle: PhiType.monoS().copyWith(color: PhiColors.fg3),
        ),
        style: PhiType.monoS().copyWith(color: PhiColors.fg0),
        cursorColor: PhiColors.voice1,
      ),
    );
  }

  Widget _rejectLine(String message) {
    return Container(
      key: PatchInlineObjectBox.rejectKey,
      width: PatchInlineObjectBox.width,
      padding: const EdgeInsets.only(top: PhiSpacing.s0),
      child: Text(
        message,
        style: PhiType.caption().copyWith(color: PhiColors.hot),
      ),
    );
  }

  Widget _completions() {
    final height = math.min(_rowHeight * _matches.length, _maxListHeight);
    return Container(
      width: PatchInlineObjectBox.width,
      height: height,
      margin: const EdgeInsets.only(top: PhiSpacing.s1),
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        borderRadius: PhiRadii.all1,
        border: Border.all(color: PhiColors.line1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemExtent: _rowHeight,
        itemCount: _matches.length,
        itemBuilder: (context, i) => _CompletionRow(
          descriptor: _matches[i],
          selected: i == _index,
          onTap: () {
            setState(() => _index = i);
            _insertCompletion();
          },
        ),
      ),
    );
  }
}

/// One catalogue row: the DSP/control dot, the type id, and the engine's own
/// one-line description — the same data the reference panel documents, so the
/// completion answers "which one is that?" without leaving the keyboard.
class _CompletionRow extends StatelessWidget {
  const _CompletionRow({
    required this.descriptor,
    required this.selected,
    required this.onTap,
  });

  final PatchObjectDescriptor descriptor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = descriptor.isDsp ? PhiColors.cool : PhiColors.fg1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: PatchInlineObjectBox.rowKey(descriptor.type),
        color: selected ? PhiColors.bg3 : null,
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: descriptor.isDsp ? PhiColors.cool : PhiColors.fg3,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: PhiSpacing.s2),
            Text(
              descriptor.type,
              style: PhiType.monoS().copyWith(
                color: selected ? PhiColors.fg0 : accent,
              ),
            ),
            const SizedBox(width: PhiSpacing.s2),
            Expanded(
              child: Text(
                descriptor.description,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: PhiType.caption().copyWith(color: PhiColors.fg3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
