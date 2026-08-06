import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_type_style.dart';
import '../../../domain/patcher/patch_args.dart';
import '../../../domain/patcher/patch_type_name.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';

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
class PatchReferencePanel extends StatelessWidget {
  const PatchReferencePanel({required this.descriptor, this.args, super.key});

  /// The object type to document, or null for the empty state.
  final PatchObjectDescriptor? descriptor;

  /// The selected canvas node's current creation-argument string, positionally
  /// aligned with [PatchObjectDescriptor.params]. Null when the reference
  /// documents a *type* (a palette tap), which has no values of its own.
  final String? args;

  /// Fixed pane width — the right column of the patcher layout.
  static const double width = 260;

  /// Key on the empty-state hint (nothing selected).
  static const Key emptyKey = Key('PatchReferencePanel.empty');

  /// Key on one parameter's current-value readout.
  static Key valueKey(String param) => Key('PatchReferencePanel.value.$param');

  @override
  Widget build(BuildContext context) {
    final d = descriptor;
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: d == null ? const _Empty() : _Reference(descriptor: d, args: args),
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
  const _Reference({required this.descriptor, this.args});

  final PatchObjectDescriptor descriptor;
  final String? args;

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
                Text(
                  '= $current',
                  key: valueKey,
                  style: PhiType.monoS().copyWith(color: PhiColors.voice1),
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
