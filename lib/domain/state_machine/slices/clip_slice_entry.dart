import '../../project/entity_address.dart';

/// One entry of a state's **clips** slice — a `clip.` entity that should be
/// playing (with its loop flag) when the state is entered (design
/// `docs/design/state-graph.md` §4, issue #240).
class ClipSliceEntry {
  const ClipSliceEntry({required this.clip, this.loop = true});

  /// Rebuilds an entry from the map [toJson] produced. Throws a
  /// [FormatException] on a missing/malformed `clip` address.
  factory ClipSliceEntry.fromJson(Map<String, Object?> json) {
    final clip = json['clip'] as String?;
    if (clip == null) {
      throw const FormatException('A clip slice entry needs a "clip" address.');
    }
    return ClipSliceEntry(
      clip: EntityAddress.parse(clip),
      loop: json['loop'] as bool? ?? true,
    );
  }

  /// The `clip.` entity captured as playing.
  final EntityAddress clip;

  /// Whether the clip plays looped, matching the captured session's flag.
  final bool loop;

  /// A copy with the clip address repointed when it equals [from].
  ClipSliceEntry withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      clip == from ? ClipSliceEntry(clip: to, loop: loop) : this;

  /// The entry as its JSON map.
  Map<String, Object?> toJson() => {'clip': clip.format(), 'loop': loop};

  @override
  bool operator ==(Object other) =>
      other is ClipSliceEntry && other.clip == clip && other.loop == loop;

  @override
  int get hashCode => Object.hash(clip, loop);
}
