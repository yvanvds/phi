/// The cosmetic, filesystem-invisible facts about a group — what an optional
/// `_group.json` holds (design `docs/design/project-registry.md` §5, review
/// decision 5).
///
/// A group is a folder, so its *existence* and its *contents* need no metadata.
/// Two things the filesystem cannot express do: an explicit child [order]
/// (directory listing is alphabetical/arbitrary) and a cosmetic library [color]
/// (per group only — there is no per-entity colour for now). Both are optional;
/// a group with neither writes no `_group.json` at all, and [isEmpty] reports
/// that case so the store can skip the file.
class GroupMetadata {
  /// Builds group metadata. [order] lists child names in display order (names
  /// not present are appended alphabetically on load); [color] is a cosmetic
  /// library colour token, or `null` for none.
  const GroupMetadata({this.order = const [], this.color});

  /// Reads metadata from a decoded `_group.json` map, tolerating either key
  /// being absent.
  factory GroupMetadata.fromJson(Map<String, Object?> json) => GroupMetadata(
    order:
        (json['order'] as List<Object?>?)
            ?.map((e) => e as String)
            .toList(growable: false) ??
        const [],
    color: json['color'] as String?,
  );

  /// The display order of this group's children, by name. Empty means "use the
  /// default" (alphabetical on load).
  final List<String> order;

  /// A cosmetic library colour token, or `null` for none.
  final String? color;

  /// Whether this metadata carries nothing worth a file on disk.
  bool get isEmpty => order.isEmpty && color == null;

  /// The metadata as the JSON map written to `_group.json`; omits empty fields
  /// so the file stays minimal and diffable.
  Map<String, Object?> toJson() => {
    if (order.isNotEmpty) 'order': order,
    if (color != null) 'color': color,
  };

  @override
  bool operator ==(Object other) =>
      other is GroupMetadata &&
      other.color == color &&
      _sameOrder(other.order, order);

  @override
  int get hashCode => Object.hash(color, Object.hashAll(order));

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
