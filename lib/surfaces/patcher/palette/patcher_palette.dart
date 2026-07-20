import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';

/// The patcher's **object palette** (design `docs/design/patcher.md` §5) — the
/// engine's whole object catalogue, grouped into [PatchObjectCategory] sections,
/// narrowed by a search box over name + description, with DSP (`~`) objects
/// visually distinct from control (`.`) objects. Each entry is draggable onto
/// the canvas (drag-to-create) and tappable to show its reference.
///
/// Pure presentation: the catalogue and current selection are passed in, so the
/// palette renders identically off the real gateway and a fake in tests. The
/// subpatch type is already filtered upstream (`PatcherGateway.objectTypes`,
/// design §10 decision 2), so it never reaches here.
class PatcherPalette extends StatefulWidget {
  const PatcherPalette({
    required this.objectTypes,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// The catalogue to render — the gateway's metadata descriptors.
  final List<PatchObjectDescriptor> objectTypes;

  /// The entry currently reflected in the reference panel, highlighted here.
  final PatchObjectDescriptor? selected;

  /// Tapping an entry selects it (drives the reference panel).
  final ValueChanged<PatchObjectDescriptor> onSelect;

  /// Fixed pane width — the left column of the patcher layout.
  static const double width = 200;

  /// Key on the search field.
  static const Key searchKey = Key('PatcherPalette.search');

  /// Key on a category section header, by category.
  static Key sectionKey(PatchObjectCategory category) =>
      Key('PatcherPalette.section.${category.name}');

  /// Key on one object entry, by its type id (e.g. `~sine`).
  static Key entryKey(String type) => Key('PatcherPalette.entry.$type');

  @override
  State<PatcherPalette> createState() => _PatcherPaletteState();
}

class _PatcherPaletteState extends State<PatcherPalette> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(PatchObjectDescriptor d) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return d.type.toLowerCase().contains(q) ||
        d.description.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.objectTypes.where(_matches).toList();
    return Container(
      width: PatcherPalette.width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(right: BorderSide(color: PhiColors.line1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const _EmptyHint(text: 'no objects match')
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: PhiSpacing.s1,
                    ),
                    children: [
                      // Enum order gives a stable canonical section order;
                      // within a section, registry (catalogue) order is kept.
                      for (final category in PatchObjectCategory.values)
                        ..._section(category, [
                          for (final d in filtered)
                            if (d.category == category) d,
                        ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(
    PatchObjectCategory category,
    List<PatchObjectDescriptor> entries,
  ) {
    if (entries.isEmpty) return const [];
    return [
      Padding(
        key: PatcherPalette.sectionKey(category),
        padding: const EdgeInsets.fromLTRB(
          PhiSpacing.s3,
          PhiSpacing.s2,
          PhiSpacing.s3,
          PhiSpacing.s1,
        ),
        child: Text(
          _categoryLabel(category),
          style: PhiType.caption().copyWith(color: PhiColors.fg2),
        ),
      ),
      for (final d in entries)
        _PaletteEntry(
          descriptor: d,
          selected:
              identical(d, widget.selected) || d.type == widget.selected?.type,
          onSelect: () => widget.onSelect(d),
        ),
    ];
  }

  static String _categoryLabel(PatchObjectCategory category) =>
      switch (category) {
        PatchObjectCategory.unset => 'other',
        PatchObjectCategory.oscillator => 'oscillators',
        PatchObjectCategory.filter => 'filters',
        PatchObjectCategory.math => 'math',
        PatchObjectCategory.generic => 'i / o',
        PatchObjectCategory.gui => 'control',
        PatchObjectCategory.time => 'timing',
        PatchObjectCategory.midi => 'midi',
      };
}

/// The palette header: a title and a live search field.
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s2,
        PhiSpacing.s2,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'objects'.toUpperCase(),
            style: PhiType.caption().copyWith(color: PhiColors.fg1),
          ),
          const SizedBox(height: PhiSpacing.s2),
          SizedBox(
            height: 26,
            child: TextField(
              key: PatcherPalette.searchKey,
              controller: controller,
              onChanged: onChanged,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
              cursorColor: PhiColors.voice1,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PhiColors.bg2,
                hintText: 'search…',
                hintStyle: PhiType.monoS().copyWith(color: PhiColors.fg3),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 14,
                  color: PhiColors.fg3,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 26,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PhiSpacing.s1,
                ),
                border: const OutlineInputBorder(
                  borderRadius: PhiRadii.all1,
                  borderSide: BorderSide(color: PhiColors.line1),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: PhiRadii.all1,
                  borderSide: BorderSide(color: PhiColors.line1),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: PhiRadii.all1,
                  borderSide: BorderSide(color: PhiColors.line2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One draggable, tappable catalogue entry. DSP objects wear the cool accent
/// (matching the audio-cable colouring); control objects stay foreground-grey.
class _PaletteEntry extends StatelessWidget {
  const _PaletteEntry({
    required this.descriptor,
    required this.selected,
    required this.onSelect,
  });

  final PatchObjectDescriptor descriptor;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = descriptor.isDsp ? PhiColors.cool : PhiColors.fg1;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Container(
        key: PatcherPalette.entryKey(descriptor.type),
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
        decoration: BoxDecoration(
          color: selected ? PhiColors.bg3 : null,
          border: selected
              ? const Border(
                  left: BorderSide(color: PhiColors.voice1, width: 2),
                )
              : null,
        ),
        child: Row(
          children: [
            _DspBadge(isDsp: descriptor.isDsp),
            const SizedBox(width: PhiSpacing.s2),
            Expanded(
              child: Text(
                descriptor.type,
                overflow: TextOverflow.ellipsis,
                style: PhiType.monoS().copyWith(
                  color: selected ? PhiColors.fg0 : accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Draggable<PatchObjectDescriptor>(
      data: descriptor,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragChip(descriptor: descriptor),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: row),
    );
  }
}

/// The `~` / `.` prefix already distinguishes DSP from control in the type id;
/// this coloured dot reinforces it at a glance (audio-cool vs control-grey).
class _DspBadge extends StatelessWidget {
  const _DspBadge({required this.isDsp});

  final bool isDsp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: isDsp ? PhiColors.cool : PhiColors.fg3,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// The floating chip shown under the pointer while dragging an entry.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.descriptor});

  final PatchObjectDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PhiSpacing.s2,
          vertical: PhiSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: PhiColors.bg3,
          border: Border.all(color: PhiColors.line2),
          borderRadius: PhiRadii.all1,
        ),
        child: Text(
          descriptor.type,
          style: PhiType.monoS().copyWith(
            color: descriptor.isDsp ? PhiColors.cool : PhiColors.fg0,
          ),
        ),
      ),
    );
  }
}

/// Shown when the search filter empties every section.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Text(text, style: PhiType.monoS().copyWith(color: PhiColors.fg3)),
    );
  }
}
