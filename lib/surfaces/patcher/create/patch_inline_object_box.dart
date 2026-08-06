import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_type_style.dart';
import '../../../domain/patcher/patch_type_name.dart';
import '../../../engine/bridge/patch_creation_args.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';

/// The **inline object box** — the Max speed path for making an object, and
/// since issue #382 for editing one: a double-click on empty canvas drops this
/// box empty at the click point and Enter instantiates (issue #358); a
/// double-click on an existing object box opens the very same widget over that
/// object, seeded with the line it prints, and Enter applies the arguments.
///
/// One widget for both because they are one gesture with two destinations: the
/// same catalogue, the same ranking, the same arrows and Tab, the same argument
/// check, the same inline refusal. What [editing] adds is only what an existing
/// object changes about the answer — see "editing in place" below.
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
/// - **A bare name shared by two objects is not resolved for you** (issue
///   #380). Four pairs collide once the prefix stops being drawn — `.+ ~+`,
///   `.- ~-`, `.* ~*`, `./ ~/`, among the most-used objects there are — so an
///   Enter on `*` refuses, names both candidates, and leaves the list up in
///   their two colours. One more keystroke settles it: an arrow moves the
///   highlight, a second Enter takes what is highlighted. Typing `~*` in full
///   is always exact and never asks. (An unambiguous bare name like `sine`
///   resolves straight through, as it always did.)
/// - **Anything after the first token is the argument string**, checked against
///   the type's documented [PatchParamDescriptor]s ([PatchCreationArgs]) before
///   anything is created — the engine crashes on arguments an object never
///   declared, and an out-of-range value silently misconfigures it.
/// - **A refusal keeps the box open** with the reason under it, so a typo is
///   corrected in place rather than costing the whole gesture. **Escape**
///   dismisses and leaves the canvas exactly as it was.
/// - **The reference panel follows the name as it settles** (issue #437):
///   the moment the typed name unambiguously names one catalogue type — typed
///   out in full, a bare name only one object answers to, a completion list
///   narrowed to a single row, or a candidate chosen by arrow/Tab/click —
///   [onResolve] reports it, so the panel is already documenting the object's
///   arguments while they are still being typed after the name. An ambiguous
///   or unknown name reports nothing: the panel keeps what it has rather than
///   flickering through guesses.
///
/// **Editing in place** ([editing] non-null, issue #382) changes exactly one
/// answer:
/// - **The object's own name is never ambiguous.** A `~*` opens reading `* 2`,
///   and that bare `*` is not the collision of issue #380 asking to be settled
///   — it is this object's name, unchanged. So the name the box opened with
///   resolves straight back to the object it opened on, and only *moving* the
///   highlight makes it a question again.
///
/// **A different type commits like any other line** (issue #383): typing `saw`
/// over a `sine 440` resolves `~saw`, checks the arguments against *that* type
/// and hands it to [onCommit], which replaces the object and carries over the
/// cables the new one still has room for. This box neither knows nor needs to
/// know which of the two edits it just committed — the type it returns says it,
/// and the one refusal that used to stand here (issue #382's seam) is gone.
///
/// Keys are owned *here* rather than on the canvas: the canvas deliberately
/// ignores every key while a descendant holds focus (issue #353), so — exactly
/// like the number box — the bindings sit between this field and the canvas,
/// where they beat both the canvas's shortcuts and Flutter's own text-editing
/// and traversal defaults.
class PatchInlineObjectBox extends StatefulWidget {
  const PatchInlineObjectBox({
    required this.objectTypes,
    required this.onCommit,
    required this.onDismiss,
    this.editing,
    this.initialText = '',
    this.onResolve,
    super.key,
  });

  /// The catalogue to complete against — the palette's own source.
  final List<PatchObjectDescriptor> objectTypes;

  /// The object this box is **editing in place**, or null when it is creating a
  /// new one (issue #382). Supplied together with [initialText], which is the
  /// line that object currently prints.
  final PatchObjectDescriptor? editing;

  /// What the field opens holding — empty for a create, the edited object's own
  /// line (`sine 440`) for an edit. Seeded **selected**, so typing replaces it
  /// and the common edit (new arguments, same object) is one gesture.
  final String initialText;

  /// Called when Enter resolved a type and its arguments passed the check — to
  /// create the object, or, when [editing], to apply the line to that one: the
  /// arguments alone if the type came back unchanged, a **retype** if it did not
  /// (issue #383).
  final void Function(PatchObjectDescriptor desc, String args) onCommit;

  /// Called when the box gives up the gesture (Escape). The canvas — and the
  /// object being edited — are left untouched.
  final VoidCallback onDismiss;

  /// Called each time the typed name comes to **unambiguously name a different
  /// catalogue type** — so the reference panel can follow the object being
  /// created while its arguments are still being typed (issue #437).
  ///
  /// Fired only on a settled answer: an exact id, a bare name one object
  /// answers to, a completion list narrowed to one row, or a candidate chosen
  /// with the arrows, Tab or a click. Never fired while the name is ambiguous
  /// or unknown, and never twice in a row for the same type. An **edit** does
  /// not fire for the name it opened with — the panel is already showing that
  /// object, values and all.
  final void Function(PatchObjectDescriptor desc)? onResolve;

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

  /// Whether the user has *chosen* a candidate for the name typed so far —
  /// arrowed the highlight onto one, tapped a row, Tab-inserted one, or been
  /// shown the two an ambiguous bare name matches. Until then a bare name that
  /// two objects answer to is refused rather than guessed at (issue #380).
  /// Cleared by the next keystroke, which makes the name a new question.
  bool _chosen = false;

  /// Whether an Enter has already been honoured. Enter arrives twice on a
  /// desktop text field — once as a key event this widget's own binding claims,
  /// once as the platform's submit action — and creating the object twice off
  /// one keypress is not a mistake the undo stack should have to describe.
  bool _committed = false;

  /// The type last reported through [PatchInlineObjectBox.onResolve], so the
  /// same answer is never announced twice (issue #437). Seeded in `initState`
  /// with whatever the initial text already resolves to — which is how an edit
  /// opening on its own name stays silent.
  String? _reportedType;

  static const double _rowHeight = 24;
  static const double _maxListHeight = 168;

  @override
  void initState() {
    super.initState();
    // An edit opens holding the object's own line, **selected**: typing
    // replaces it outright (the Max habit), while an arrow or a click puts the
    // caret in it for a one-character correction.
    final seed = widget.initialText;
    if (seed.isNotEmpty) {
      _text.value = TextEditingValue(
        text: seed,
        selection: TextSelection(baseOffset: 0, extentOffset: seed.length),
      );
    }
    _matches = _matchesFor(_name);
    // What the seed already resolves to is not news: an edit opens on its own
    // line, and the panel is already showing that very object (issue #437).
    _reportedType = _resolvedUnambiguously?.type;
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
      final bare = PatchTypeName.bare(type);
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

  /// Every catalogue entry a *bare* [name] answers to — one for `sine`, two for
  /// `*` (`.*` and `~*`). The ambiguity set of issue #380.
  List<PatchObjectDescriptor> _bareCandidates(String name) {
    final q = name.toLowerCase();
    return [
      for (final d in widget.objectTypes)
        if (PatchTypeName.bare(d.type.toLowerCase()) == q) d,
    ];
  }

  /// The catalogue entry whose id was typed out in full, or null.
  PatchObjectDescriptor? _exact(String name) {
    for (final d in widget.objectTypes) {
      if (d.type == name) return d;
    }
    return null;
  }

  /// The one type the current text **unambiguously** names, or null while the
  /// name is still a question (issue #437).
  ///
  /// Deliberately stricter than [_resolved], which exists to give Enter an
  /// answer and so falls back on the highlight even when nothing chose it: a
  /// bare `*` must not flick the reference panel to whichever of the two `*`s
  /// happens to rank first. Here a name counts only when it is typed out in
  /// full, is the edited object's own, has been *chosen* (arrow / Tab / click),
  /// answers to exactly one object bare, or has narrowed the completion list to
  /// a single row.
  PatchObjectDescriptor? get _resolvedUnambiguously {
    final name = _name;
    if (name.isEmpty) return null;
    final exact = _exact(name);
    if (exact != null) return exact;
    if (_isOwnName(name)) return widget.editing;
    if (_chosen && _matches.isNotEmpty) {
      return _matches[_index.clamp(0, _matches.length - 1)];
    }
    final bare = _bareCandidates(name);
    if (bare.length == 1) return bare.single;
    if (_matches.length == 1) return _matches.single;
    return null;
  }

  /// Report a newly-settled name through [PatchInlineObjectBox.onResolve] —
  /// once per answer, silence while the name is ambiguous or unknown, so the
  /// reference panel follows what is typed without flickering through guesses.
  void _notifyResolve() {
    final target = _resolvedUnambiguously;
    if (target == null || target.type == _reportedType) return;
    _reportedType = target.type;
    widget.onResolve?.call(target);
  }

  void _onChanged(String _) {
    setState(() {
      _matches = _matchesFor(_name);
      _index = 0;
      _reject = null;
      _chosen = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _notifyResolve();
  }

  void _move(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _index = (_index + delta) % _matches.length;
      if (_index < 0) _index += _matches.length;
      _chosen = true;
    });
    _revealSelected();
    _notifyResolve();
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

  /// Whether [name] is the **edited object's own name** — its bare id, left as
  /// the box opened with it (issue #382).
  ///
  /// False the moment the user has *chosen* something else: an arrow onto
  /// another row makes the name a question again, exactly as it would in a
  /// create.
  bool _isOwnName(String name) {
    final editing = widget.editing;
    if (editing == null || _chosen) return false;
    return PatchTypeName.bare(editing.type) == name.toLowerCase();
  }

  /// The type the current text would instantiate: an exact catalogue id when the
  /// name already is one, the edited object itself when its own name is still
  /// standing, else whatever the highlight is on.
  PatchObjectDescriptor? get _resolved {
    final name = _name;
    if (name.isEmpty) return null;
    final exact = _exact(name);
    if (exact != null) return exact;
    // An unchanged bare name keeps the object's current type: `*` over a `~*`
    // means `~*`, not the `.*` that happens to rank first (issues #380, #382).
    if (_isOwnName(name)) return widget.editing;
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
      _chosen = true;
    });
    _notifyResolve();
  }

  /// Enter: resolve the name, check the arguments, and commit — or refuse
  /// inline and stay open.
  void _submit() {
    if (_committed) return;
    final name = _name;
    if (name.isEmpty) {
      setState(() => _reject = 'type an object name');
      return;
    }
    // A bare name two objects answer to is not guessed at (issue #380). The
    // list is already showing both, in the two colours that tell them apart;
    // this refusal is what makes you look at it. An arrow (or a second Enter,
    // taking the highlight) then decides, and typing the id out in full never
    // gets here at all. An *edit* whose name is still the object's own is not
    // that question — the object already answered it.
    if (!_chosen && _exact(name) == null && !_isOwnName(name)) {
      final candidates = _bareCandidates(name);
      if (candidates.length > 1) {
        setState(() {
          _chosen = true;
          _reject =
              'pick one · ${[for (final d in candidates) d.type].join(' or ')}';
        });
        return;
      }
    }
    final desc = _resolved;
    if (desc == null) {
      setState(() => _reject = 'unknown object · $_name');
      return;
    }
    // A **different** type is a retype (issue #383) and commits like any other
    // line: the arguments are checked against the type that was *typed*, not
    // against the one that is there, and the host replaces the object. Nothing
    // here has to know that — which is why the seam was one refusal.
    final checked = PatchCreationArgs.check(desc, _typedArgs);
    final problem = checked.problem;
    if (problem != null) {
      setState(() => _reject = problem);
      return;
    }
    _committed = true;
    widget.onCommit(desc, checked.args);
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

/// One catalogue row: the object's **bare** name in its domain colour, and the
/// engine's own one-line description — the same data the reference panel
/// documents, so the completion answers "which one is that?" without leaving
/// the keyboard.
///
/// The leading DSP/control dot is gone with the prefix (issue #380); the name's
/// colour says it, and the description says the rest. Two rows reading `*` in
/// two colours is exactly the picture an ambiguous name needs.
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
    final accent = PatchTypeStyle.color(descriptor.isDsp);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: PatchInlineObjectBox.rowKey(descriptor.type),
        color: selected ? PhiColors.bg3 : null,
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
        child: Row(
          children: [
            Text(
              PatchTypeName.bare(descriptor.type),
              style: PhiType.monoS().copyWith(color: accent),
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
