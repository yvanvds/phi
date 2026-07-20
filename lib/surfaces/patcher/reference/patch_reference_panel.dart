import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';

/// The patcher's **reference panel** (design `docs/design/patcher.md` §5): the
/// engine's own documentation for the selected object type (from the palette or
/// a canvas node) — its description, per-inlet docs (accepted kinds + range),
/// per-outlet docs (data type + range), and creation parameters (default +
/// range). Every string rendered is the engine's metadata; there is no hardcoded
/// catalogue, so an object the engine adds documents itself for free.
class PatchReferencePanel extends StatelessWidget {
  const PatchReferencePanel({required this.descriptor, super.key});

  /// The object type to document, or null for the empty state.
  final PatchObjectDescriptor? descriptor;

  /// Fixed pane width — the right column of the patcher layout.
  static const double width = 260;

  /// Key on the empty-state hint (nothing selected).
  static const Key emptyKey = Key('PatchReferencePanel.empty');

  @override
  Widget build(BuildContext context) {
    final d = descriptor;
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: d == null ? const _Empty() : _Reference(descriptor: d),
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
  const _Reference({required this.descriptor});

  final PatchObjectDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final d = descriptor;
    final accent = d.isDsp ? PhiColors.cool : PhiColors.fg0;
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
              for (final p in d.params)
                _PortEntry(
                  lead: p.name,
                  doc: p.doc,
                  meta: [
                    'default ${p.defaultValue}',
                    if (p.range.isNotEmpty) 'range ${p.range}',
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
class _PortEntry extends StatelessWidget {
  const _PortEntry({required this.lead, required this.doc, required this.meta});

  final String lead;
  final String doc;
  final List<String> meta;

  @override
  Widget build(BuildContext context) {
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
          Text(lead, style: PhiType.monoS().copyWith(color: PhiColors.fg0)),
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
