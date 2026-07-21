import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/tokens/phi_voices.dart';
import '../../../domain/code/completion/phi_completion_item.dart';
import '../../../domain/code/completion/phi_completion_item_kind.dart';
import 'phi_completion_prompt.dart';

/// The registry-driven completion popup — the overlay `re_editor` shows for a
/// `phi` namespace (design `docs/design/live-coding.md` §6).
///
/// Each row is Phi-flavoured: a voice carries its colour swatch, a clip its
/// bar-length badge, a group a chevron, a method a call marker. The currently
/// selected row (driven by up/down through `re_editor`'s own navigation) is
/// highlighted; tapping a row — or pressing Enter — inserts its bare identifier.
class PhiCompletionListView extends StatefulWidget
    implements PreferredSizeWidget {
  const PhiCompletionListView({
    required this.notifier,
    required this.onSelected,
    super.key,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  static const double _rowHeight = 26;
  static const double _width = 260;
  static const double _maxHeight = 220;

  /// Key on a row, by the identifier it offers.
  static Key rowKey(String identifier) =>
      ValueKey('phi-completion-row-$identifier');

  /// Key on a voice row's colour swatch, by identifier.
  static Key swatchKey(String identifier) =>
      ValueKey('phi-completion-swatch-$identifier');

  /// Key on a group row's chevron, by identifier.
  static Key chevronKey(String identifier) =>
      ValueKey('phi-completion-chevron-$identifier');

  @override
  Size get preferredSize => Size(
    _width,
    math.min(_rowHeight * notifier.value.prompts.length, _maxHeight) + 2,
  );

  @override
  State<PhiCompletionListView> createState() => _PhiCompletionListViewState();
}

class _PhiCompletionListViewState extends State<PhiCompletionListView> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final value = widget.notifier.value;
    return Container(
      constraints: BoxConstraints.loose(widget.preferredSize),
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PhiColors.line1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: value.prompts.length,
        itemBuilder: (context, index) {
          final prompt = value.prompts[index];
          final item = prompt is PhiCompletionPrompt ? prompt.item : null;
          return _CompletionRow(
            identifier: prompt.word,
            item: item,
            input: value.input,
            selected: index == value.index,
            onTap: () =>
                widget.onSelected(value.copyWith(index: index).autocomplete),
          );
        },
      ),
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow({
    required this.identifier,
    required this.item,
    required this.input,
    required this.selected,
    required this.onTap,
  });

  final String identifier;
  final PhiCompletionItem? item;
  final String input;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        key: PhiCompletionListView.rowKey(identifier),
        height: PhiCompletionListView._rowHeight,
        color: selected ? PhiColors.bg2 : null,
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
        child: Row(
          children: [
            SizedBox(width: 16, child: Center(child: _leading())),
            const SizedBox(width: PhiSpacing.s2),
            Expanded(child: _label()),
            ..._trailing(),
          ],
        ),
      ),
    );
  }

  Widget _leading() {
    final item = this.item;
    if (item == null) return const SizedBox.shrink();
    switch (item.kind) {
      case PhiCompletionItemKind.group:
        return Icon(
          Icons.chevron_right,
          key: PhiCompletionListView.chevronKey(identifier),
          size: 14,
          color: PhiColors.fg2,
        );
      case PhiCompletionItemKind.entity:
        if (item.namespace == 'voice') {
          return Container(
            key: PhiCompletionListView.swatchKey(identifier),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: PhiVoices.colorForToken(item.colorToken ?? 'voice1'),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }
        return Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: PhiColors.fg3,
            shape: BoxShape.circle,
          ),
        );
      case PhiCompletionItemKind.method:
        return Text(
          'ƒ',
          style: PhiType.monoS().copyWith(color: PhiColors.voice1),
        );
    }
  }

  Widget _label() {
    final base = PhiType.monoS().copyWith(color: PhiColors.fg1);
    final split = math.min(input.length, identifier.length);
    if (split <= 0) {
      return Text(
        identifier,
        style: base,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }
    return RichText(
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      text: TextSpan(
        children: [
          TextSpan(
            text: identifier.substring(0, split),
            style: base.copyWith(
              color: PhiColors.voice1,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: identifier.substring(split), style: base),
        ],
      ),
    );
  }

  List<Widget> _trailing() {
    final item = this.item;
    if (item == null) return const [];
    if (item.bars != null) {
      return [
        Text(
          '${item.bars} ${item.bars == 1 ? 'bar' : 'bars'}',
          style: PhiType.caption().copyWith(color: PhiColors.fg3),
        ),
      ];
    }
    if (item.kind == PhiCompletionItemKind.method) {
      return [
        Text('()', style: PhiType.monoS().copyWith(color: PhiColors.fg3)),
      ];
    }
    return const [];
  }
}
