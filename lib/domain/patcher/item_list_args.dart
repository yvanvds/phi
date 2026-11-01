import 'patch_args.dart';

/// The creation arguments of a `.umenu`, `.radiogroup` or `.tab` — an optional
/// leading `multi` keyword, then the items (issue #471).
///
/// Read the way the engine's `gItemListBase::ShapeItems` reads them:
///
/// - **no items**: [defaultCount] of them, named by their index;
/// - **exactly one item that reads as a number of at least 1**: that many
///   items (truncated, at most [maxItems]), named by their index;
/// - **anything else**: one item per word, in order, at most [maxItems].
///
/// Every item therefore has a name, which is what the control draws.
class ItemListArgs {
  const ItemListArgs({required this.labels, this.multi = false});

  factory ItemListArgs.parse(String args) {
    final words = splitPatchArgs(args);
    final multi = words.isNotEmpty && words.first == multiKeyword;
    final items = words.skip(multi ? 1 : 0).toList();
    if (items.isEmpty) {
      return ItemListArgs(multi: multi, labels: _indexed(defaultCount));
    }
    if (items.length == 1) {
      final count = double.tryParse(items.single);
      if (count != null && count.isFinite && count >= 1) {
        return ItemListArgs(
          multi: multi,
          labels: _indexed(count.truncate().clamp(1, maxItems)),
        );
      }
    }
    return ItemListArgs(multi: multi, labels: items.take(maxItems).toList());
  }

  /// The first-word keyword that lets several items be selected at once.
  static const String multiKeyword = 'multi';

  /// Items a control with no item arguments has — the engine's
  /// `DEFAULT_ITEMS`.
  static const int defaultCount = 2;

  /// Most items a control holds — the engine's `MAX_ITEMS`.
  static const int maxItems = 256;

  /// Whether several items can be selected at once.
  final bool multi;

  /// Every item's name, in order. Never empty for a parsed argument string.
  final List<String> labels;

  /// How many items the control holds.
  int get count => labels.length;

  /// The selected items in a GUI value the engine reported, read for this
  /// shape: the index alone in single select, one `0`/`1` flag per item with
  /// [multi]. Anything outside the item list is dropped, so a stale value read
  /// across a retype never points past the end.
  Set<int> selectionOf(String guiValue) {
    final words = splitPatchArgs(guiValue);
    if (!multi) {
      final index = num.tryParse(words.isEmpty ? '' : words.first)?.truncate();
      return index == null || index < 0 || index >= count ? {} : {index};
    }
    return {
      for (var i = 0; i < words.length && i < count; i++)
        if ((num.tryParse(words[i]) ?? 0) != 0) i,
    };
  }

  static List<String> _indexed(int count) => [
    for (var i = 0; i < count; i++) '$i',
  ];
}
