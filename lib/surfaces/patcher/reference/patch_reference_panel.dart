import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Theme;

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_note_swatch.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_type_style.dart';
import '../../../domain/patcher/keyboard_layout.dart';
import '../../../domain/patcher/patch_args.dart';
import '../../../domain/patcher/patch_object_types.dart';
import '../../../domain/patcher/patch_type_name.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';
import '../tutorial/patch_word_button.dart';
import 'patch_keyboard_settings.dart';
import 'patch_subpatch_summary.dart';

/// The patcher's **reference panel** (design `docs/design/patcher.md` §5): the
/// engine's own documentation for the selected object type (from the palette or
/// a canvas node) — its description, per-inlet docs (accepted kinds + range),
/// per-outlet docs (data type + range), and creation parameters (default +
/// range). Every string rendered is the engine's metadata; there is no hardcoded
/// catalogue, so an object the engine adds documents itself for free.
///
/// When the reference comes from a **canvas node** rather than a palette entry,
/// [args] carries that node's current creation arguments and each documented
/// parameter is shown with the value it actually holds, so selecting a node
/// answers "what is this set to" without opening a dialog (issue #356).
///
/// A selected **note** also gets a colour row (issue #511): the plain look and
/// every [PhiNoteSwatch], the current one ringed. A tap reports the chosen
/// token name through [onNoteColor] (`''` for plain), which the surface
/// journals — so the panel itself never edits anything.
///
/// A selected **`.kslider`** gets keyboard rows the same way (issue #515):
/// its [keyboardRange] and [keyboardVelocity], edited through
/// [onKeyboardRange] / [onKeyboardVelocity] ([PatchKeyboardSettings]).
///
/// When the documented type has a bundled tutorial, the surface passes
/// [onOpenTutorial] and an **Open tutorial** button sits under the heading
/// (issue #489) — for a palette tap and a canvas selection alike.
class PatchReferencePanel extends StatelessWidget {
  const PatchReferencePanel({
    required this.descriptor,
    this.args,
    this.noteColor,
    this.onNoteColor,
    this.keyboardRange,
    this.keyboardVelocity,
    this.onKeyboardRange,
    this.onKeyboardVelocity,
    this.onOpenTutorial,
    this.subpatch,
    this.onOpenSubpatch,
    this.onMakeAbstraction,
    this.onDetach,
    super.key,
  });

  /// The selected subpatch box's name and pin counts (issue #481), or null for
  /// anything else — a palette tap documents the type, not one box.
  final PatchSubpatchSummary? subpatch;

  /// Opens the selected subpatch in its window. Null hides the button.
  final VoidCallback? onOpenSubpatch;

  /// Makes the selected ordinary subpatch an instance of a new patch (issue
  /// #553). Null hides the button.
  final VoidCallback? onMakeAbstraction;

  /// Makes the selected instance an ordinary subpatch (issue #553). Null hides
  /// the button.
  final VoidCallback? onDetach;

  /// Key on the subpatch section's definition readout.
  static const Key subpatchDefinitionKey = Key(
    'PatchReferencePanel.subpatch.definition',
  );

  /// Key on the subpatch section's make-abstraction button.
  static const Key makeAbstractionKey = Key(
    'PatchReferencePanel.subpatch.makeAbstraction',
  );

  /// Key on the subpatch section's detach button.
  static const Key detachKey = Key('PatchReferencePanel.subpatch.detach');

  /// Key on the subpatch section's name readout.
  static const Key subpatchNameKey = Key('PatchReferencePanel.subpatch.name');

  /// Key on the subpatch section's inlet-count readout.
  static const Key subpatchInletsKey = Key(
    'PatchReferencePanel.subpatch.inlets',
  );

  /// Key on the subpatch section's outlet-count readout.
  static const Key subpatchOutletsKey = Key(
    'PatchReferencePanel.subpatch.outlets',
  );

  /// Key on the subpatch section's open button.
  static const Key openSubpatchKey = Key('PatchReferencePanel.subpatch.open');

  /// The object type to document, or null for the empty state.
  final PatchObjectDescriptor? descriptor;

  /// The selected canvas node's current creation-argument string, positionally
  /// aligned with [PatchObjectDescriptor.params]. Null when the reference
  /// documents a *type* (a palette tap), which has no values of its own.
  final String? args;

  /// The selected note's swatch token name (`''` for plain). Only read while
  /// [onNoteColor] is set.
  final String? noteColor;

  /// Called with the swatch token name a tap picked (`''` for plain). Null
  /// hides the colour row — a palette tap, or a node that is not a note.
  final ValueChanged<String>? onNoteColor;

  /// The selected `.kslider`'s visible range. The keyboard rows show only
  /// while it and both keyboard callbacks are set.
  final KeyboardLayout? keyboardRange;

  /// The selected `.kslider`'s fixed press velocity, null for depth.
  final int? keyboardVelocity;

  /// Called with the range a keyboard step picked.
  final ValueChanged<KeyboardLayout>? onKeyboardRange;

  /// Called with the fixed velocity a keyboard step picked (null for depth).
  final ValueChanged<int?>? onKeyboardVelocity;

  /// Opens the documented type's tutorial. Null hides the button — the type
  /// has no tutorial (or nothing is documented).
  final VoidCallback? onOpenTutorial;

  /// Key on the "Open tutorial" button.
  static const Key openTutorialKey = Key('PatchReferencePanel.openTutorial');

  /// Fixed pane width — the right column of the patcher layout.
  static const double width = 260;

  /// Key on the empty-state hint (nothing selected).
  static const Key emptyKey = Key('PatchReferencePanel.empty');

  /// Key on one parameter's current-value readout.
  static Key valueKey(String param) => Key('PatchReferencePanel.value.$param');

  /// Key on one note-colour chip — [name] is the swatch token name, `''` the
  /// plain look.
  static Key noteColorKey(String name) =>
      Key('PatchReferencePanel.noteColor.${name.isEmpty ? 'none' : name}');

  @override
  Widget build(BuildContext context) {
    final d = descriptor;
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: d == null
          ? const _Empty()
          : _Reference(
              descriptor: d,
              args: args,
              onOpenTutorial: onOpenTutorial,
              subpatch: subpatch,
              onOpenSubpatch: onOpenSubpatch,
              onMakeAbstraction: onMakeAbstraction,
              onDetach: onDetach,
              noteColor: noteColor ?? '',
              onNoteColor: PatchTypeName.isNote(d.type) ? onNoteColor : null,
              keyboard: switch ((
                keyboardRange,
                onKeyboardRange,
                onKeyboardVelocity,
              )) {
                (final range?, final onRange?, final onVelocity?)
                    when d.type == PatchObjectTypes.gKslider =>
                  PatchKeyboardSettings(
                    range: range,
                    velocity: keyboardVelocity,
                    onRange: onRange,
                    onVelocity: onVelocity,
                  ),
                _ => null,
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: PatchReferencePanel.emptyKey,
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Text(
        'select an object to see its reference',
        style: PhiType.monoS().copyWith(color: PhiColors.fg3),
      ),
    );
  }
}

class _Reference extends StatelessWidget {
  const _Reference({
    required this.descriptor,
    required this.noteColor,
    this.args,
    this.onNoteColor,
    this.keyboard,
    this.onOpenTutorial,
    this.subpatch,
    this.onOpenSubpatch,
    this.onMakeAbstraction,
    this.onDetach,
  });

  final PatchSubpatchSummary? subpatch;
  final VoidCallback? onOpenSubpatch;
  final VoidCallback? onMakeAbstraction;
  final VoidCallback? onDetach;
  final PatchObjectDescriptor descriptor;
  final String? args;
  final VoidCallback? onOpenTutorial;
  final String noteColor;
  final ValueChanged<String>? onNoteColor;
  final Widget? keyboard;

  @override
  Widget build(BuildContext context) {
    final d = descriptor;
    // Coloured like the box and the palette row (issue #380) — but the heading
    // keeps the **canonical** `~sine` / `.metro`, prefix and all. This is the
    // reference: it is where you look the exact name up in order to type it.
    final accent = PatchTypeStyle.color(d.isDsp);
    // Positional, exactly as `setParams` reads them, so the nth value lines up
    // with the nth documented parameter. A palette tap documents a type and
    // supplies none. The note's single parameter is **free text** (issue
    // #436): its value is the whole string, not the first word of it.
    final values = args == null
        ? const <String>[]
        : PatchTypeName.isNote(d.type)
        ? [if (args!.trim().isNotEmpty) args!.trim()]
        : splitPatchArgs(args!);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s2),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PhiSpacing.s3,
            PhiSpacing.s1,
            PhiSpacing.s3,
            PhiSpacing.s1,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  d.type,
                  style: PhiType.monoL().copyWith(color: accent),
                ),
              ),
              _KindTag(isDsp: d.isDsp),
            ],
          ),
        ),
        if (onOpenTutorial != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PhiSpacing.s3,
              PhiSpacing.s1,
              PhiSpacing.s3,
              PhiSpacing.s1,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PatchWordButton(
                key: PatchReferencePanel.openTutorialKey,
                label: 'open tutorial',
                color: PhiColors.voice1,
                tooltip: 'a playable demo patch of this object',
                onTap: onOpenTutorial!,
              ),
            ),
          ),
        if (subpatch case final box?)
          _Section(
            title: 'subpatch',
            children: [
              _PortEntry(
                lead: 'name',
                doc: '',
                meta: const [],
                value: box.name.isEmpty ? 'untitled' : box.name,
                valueKey: PatchReferencePanel.subpatchNameKey,
              ),
              if (box.definition case final definition?)
                _PortEntry(
                  lead: 'definition',
                  doc: box.definitionFollowed ? '' : 'not followed',
                  meta: const [],
                  value: definition,
                  valueKey: PatchReferencePanel.subpatchDefinitionKey,
                ),
              _PortEntry(
                lead: 'inlets',
                doc: '',
                meta: const [],
                value: '${box.inlets}',
                valueKey: PatchReferencePanel.subpatchInletsKey,
              ),
              _PortEntry(
                lead: 'outlets',
                doc: '',
                meta: const [],
                value: '${box.outlets}',
                valueKey: PatchReferencePanel.subpatchOutletsKey,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PhiSpacing.s3,
                  PhiSpacing.s1,
                  PhiSpacing.s3,
                  PhiSpacing.s1,
                ),
                child: Wrap(
                  spacing: PhiSpacing.s1,
                  runSpacing: PhiSpacing.s1,
                  children: [
                    if (onOpenSubpatch case final open?)
                      PatchWordButton(
                        key: PatchReferencePanel.openSubpatchKey,
                        label: box.definition == null
                            ? 'open subpatch'
                            : 'open definition',
                        color: PhiColors.voice1,
                        tooltip: box.definition == null
                            ? 'open the subpatch in its own window'
                            : 'open the patch this box is an instance of',
                        onTap: open,
                      ),
                    if (onMakeAbstraction case final make?)
                      PatchWordButton(
                        key: PatchReferencePanel.makeAbstractionKey,
                        label: 'make abstraction',
                        tooltip: 'make this box an instance of a new patch',
                        onTap: make,
                      ),
                    if (onDetach case final detach?)
                      PatchWordButton(
                        key: PatchReferencePanel.detachKey,
                        label: 'detach',
                        tooltip:
                            'keep what the box holds and stop following the '
                            'definition',
                        onTap: detach,
                      ),
                  ],
                ),
              ),
            ],
          ),
        if (d.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PhiSpacing.s3,
              PhiSpacing.s1,
              PhiSpacing.s3,
              PhiSpacing.s2,
            ),
            child: Text(
              d.description,
              style: PhiType.small().copyWith(color: PhiColors.fg1),
            ),
          ),
        if (d.inlets.isNotEmpty)
          _Section(
            title: 'inlets',
            children: [
              for (var i = 0; i < d.inlets.length; i++)
                _PortEntry(
                  lead: '[$i] ${d.inlets[i].label}',
                  doc: d.inlets[i].doc,
                  meta: [
                    'accepts ${_acceptsLabel(d.inlets[i].accepts)}',
                    if (d.inlets[i].range.isNotEmpty)
                      'range ${d.inlets[i].range}',
                  ],
                ),
            ],
          ),
        if (d.outlets.isNotEmpty)
          _Section(
            title: 'outlets',
            children: [
              for (var i = 0; i < d.outlets.length; i++)
                _PortEntry(
                  lead: '[$i] ${d.outlets[i].label}',
                  doc: d.outlets[i].doc,
                  meta: [
                    'type ${d.outlets[i].type.name}',
                    if (d.outlets[i].range.isNotEmpty)
                      'range ${d.outlets[i].range}',
                  ],
                ),
            ],
          ),
        if (d.params.isNotEmpty)
          _Section(
            title: 'params',
            children: [
              for (var i = 0; i < d.params.length; i++)
                _PortEntry(
                  lead: d.params[i].name,
                  doc: d.params[i].doc,
                  // The value this node actually holds. Omitted rather than
                  // guessed when the node carries fewer arguments than the type
                  // documents — the `default` below already says what the engine
                  // fell back to.
                  value: i < values.length ? values[i] : null,
                  valueKey: PatchReferencePanel.valueKey(d.params[i].name),
                  meta: [
                    'default ${d.params[i].defaultValue}',
                    if (d.params[i].range.isNotEmpty)
                      'range ${d.params[i].range}',
                  ],
                ),
            ],
          ),
        if (onNoteColor case final pick?)
          _Section(
            title: 'colour',
            children: [_NoteColorRow(current: noteColor, onPick: pick)],
          ),
        if (keyboard case final rows?)
          _Section(title: 'keyboard', children: [rows]),
      ],
    );
  }

  /// Accepted inlet kinds in a stable, enum-canonical order (so the rendered
  /// string never depends on `Set` iteration order).
  static String _acceptsLabel(Set<PatchInletAccept> accepts) => [
    for (final a in PatchInletAccept.values)
      if (accepts.contains(a)) a.name,
  ].join(', ');
}

/// The note colour picker (issue #511): a plain chip, then one chip per
/// [PhiNoteSwatch] painted in its field and frame for the current theme. The
/// current colour is ringed in the foreground.
class _NoteColorRow extends StatelessWidget {
  const _NoteColorRow({required this.current, required this.onPick});

  final String current;
  final ValueChanged<String> onPick;

  static const double _chip = 20;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    Widget chip(String name, String label, Color field, Color frame) {
      final selected = name == current;
      return Semantics(
        button: true,
        selected: selected,
        label: 'note colour $label',
        child: GestureDetector(
          key: PatchReferencePanel.noteColorKey(name),
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(name),
          child: Container(
            width: _chip + 6,
            height: _chip + 6,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: PhiRadii.all2,
              border: Border.all(
                color: selected ? PhiColors.fg0 : const Color(0x00000000),
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: field,
                borderRadius: PhiRadii.all1,
                border: Border.all(color: frame),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s3,
        PhiSpacing.s1,
      ),
      child: Wrap(
        spacing: PhiSpacing.s1,
        runSpacing: PhiSpacing.s1,
        children: [
          chip('', 'plain', PhiColors.noteBg, PhiColors.noteLine),
          for (final s in PhiNoteSwatch.all)
            chip(s.name, s.label, s.bg(brightness), s.line(brightness)),
        ],
      ),
    );
  }
}

/// A small `dsp` / `control` chip echoing the palette's DSP distinction.
class _KindTag extends StatelessWidget {
  const _KindTag({required this.isDsp});

  final bool isDsp;

  @override
  Widget build(BuildContext context) {
    final color = isDsp ? PhiColors.cool : PhiColors.fg2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s1),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        border: Border.all(color: PhiColors.line1),
      ),
      child: Text(
        isDsp ? 'dsp' : 'control',
        style: PhiType.caption().copyWith(color: color),
      ),
    );
  }
}

/// A titled group of reference rows (INLETS / OUTLETS / PARAMS).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(top: PhiSpacing.s2),
          padding: const EdgeInsets.fromLTRB(
            PhiSpacing.s3,
            PhiSpacing.s2,
            PhiSpacing.s3,
            PhiSpacing.s1,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PhiColors.line1)),
          ),
          child: Text(
            title.toUpperCase(),
            style: PhiType.caption().copyWith(color: PhiColors.fg2),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// One documented port or parameter: a lead line, its doc, and a dim meta line.
///
/// A parameter also carries [value] — what the selected node is *currently* set
/// to — right-aligned on the lead row, so the answer sits beside the question
/// instead of buried in the dim metadata (issue #356). Ports never have one.
class _PortEntry extends StatelessWidget {
  const _PortEntry({
    required this.lead,
    required this.doc,
    required this.meta,
    this.value,
    this.valueKey,
  });

  final String lead;
  final String doc;
  final List<String> meta;
  final String? value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s3,
        PhiSpacing.s1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lead,
                  style: PhiType.monoS().copyWith(color: PhiColors.fg0),
                ),
              ),
              if (current != null)
                // Flexible and one line: a note's value is its whole text — a
                // paragraph since issue #488 — and must ellipsise, not push the
                // row off the panel.
                Flexible(
                  child: Text(
                    '= $current',
                    key: valueKey,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: PhiType.monoS().copyWith(color: PhiColors.voice1),
                  ),
                ),
            ],
          ),
          if (doc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: PhiSpacing.s0),
              child: Text(
                doc,
                style: PhiType.small().copyWith(color: PhiColors.fg1),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: PhiSpacing.s0),
              child: Text(
                meta.join('  ·  '),
                style: PhiType.caption().copyWith(color: PhiColors.fg3),
              ),
            ),
        ],
      ),
    );
  }
}
