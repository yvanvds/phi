import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_type_style.dart';
import '../../../domain/patcher/patch_type_name.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';
import '../palette/patcher_palette.dart';

/// The **Tutorials browser** (issue #489): every object type that has a
/// bundled tutorial, grouped into [PatchObjectCategory] sections exactly as the
/// object palette groups them, narrowed by a search over name + description.
/// A tap opens that type's tutorial.
///
/// Pure presentation: the catalogue, the set of types with a tutorial and the
/// open callback are handed in. A type the index names but the engine does not
/// list (an object not in this build) is left out — there is nothing to open
/// it against.
class PatchTutorialBrowser extends StatefulWidget {
  const PatchTutorialBrowser({
    required this.objectTypes,
    required this.tutorialTypes,
    required this.onOpen,
    super.key,
  });

  /// The engine's object catalogue (for categories and descriptions).
  final List<PatchObjectDescriptor> objectTypes;

  /// The canonical ids that have a tutorial.
  final Set<String> tutorialTypes;

  /// Open the tutorial for a type.
  final ValueChanged<String> onOpen;

  /// Key on the search field.
  static const Key searchKey = Key('PatchTutorialBrowser.search');

  /// Key on one entry, by canonical type id.
  static Key entryKey(String type) => Key('PatchTutorialBrowser.entry.$type');

  /// Key on the empty hint.
  static const Key emptyKey = Key('PatchTutorialBrowser.empty');

  @override
  State<PatchTutorialBrowser> createState() => _PatchTutorialBrowserState();
}

class _PatchTutorialBrowserState extends State<PatchTutorialBrowser> {
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
    final entries = [
      for (final d in widget.objectTypes)
        if (widget.tutorialTypes.contains(d.type) && _matches(d)) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(PhiSpacing.s2),
          child: SizedBox(
            height: 26,
            child: TextField(
              key: PatchTutorialBrowser.searchKey,
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
              cursorColor: PhiColors.voice1,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PhiColors.bg2,
                hintText: 'search tutorials…',
                hintStyle: PhiType.monoS().copyWith(color: PhiColors.fg3),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PhiSpacing.s2,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Padding(
                  key: PatchTutorialBrowser.emptyKey,
                  padding: const EdgeInsets.all(PhiSpacing.s3),
                  child: Text(
                    widget.tutorialTypes.isEmpty
                        ? 'no tutorials yet'
                        : 'no tutorials match',
                    style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: PhiSpacing.s1),
                  children: [
                    for (final category in PatchObjectCategory.values)
                      ..._section(category, [
                        for (final d in entries)
                          if (d.category == category) d,
                      ]),
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _section(
    PatchObjectCategory category,
    List<PatchObjectDescriptor> entries,
  ) {
    if (entries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          PhiSpacing.s3,
          PhiSpacing.s2,
          PhiSpacing.s3,
          PhiSpacing.s1,
        ),
        child: Text(
          PatcherPalette.categoryLabel(category),
          style: PhiType.caption().copyWith(color: PhiColors.fg2),
        ),
      ),
      for (final d in entries)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: PatchTutorialBrowser.entryKey(d.type),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOpen(d.type),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
              alignment: Alignment.centerLeft,
              child: Text(
                PatchTypeName.bare(d.type),
                overflow: TextOverflow.ellipsis,
                style: PhiType.monoS().copyWith(
                  color: PatchTypeStyle.color(d.isDsp),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
