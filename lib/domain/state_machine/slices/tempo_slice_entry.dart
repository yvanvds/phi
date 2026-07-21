import '../../project/entity_address.dart';

/// One entry of a state's **tempos** slice — the captured tempo of a
/// `domain.` clock (design `docs/design/state-graph.md` §4, issue #240).
class TempoSliceEntry {
  const TempoSliceEntry({required this.domain, required this.bpm});

  /// Rebuilds an entry from the map [toJson] produced. Throws a
  /// [FormatException] on a missing/malformed `domain` address or bpm.
  factory TempoSliceEntry.fromJson(Map<String, Object?> json) {
    final domain = json['domain'] as String?;
    final bpm = (json['bpm'] as num?)?.toDouble();
    if (domain == null || bpm == null) {
      throw const FormatException(
        'A tempo slice entry needs a "domain" address and a "bpm".',
      );
    }
    return TempoSliceEntry(domain: EntityAddress.parse(domain), bpm: bpm);
  }

  /// The `domain.` entity whose tempo is captured.
  final EntityAddress domain;

  /// The captured tempo, beats per minute.
  final double bpm;

  /// A copy with the domain address repointed when it equals [from].
  TempoSliceEntry withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      domain == from ? TempoSliceEntry(domain: to, bpm: bpm) : this;

  /// The entry as its JSON map.
  Map<String, Object?> toJson() => {'domain': domain.format(), 'bpm': bpm};

  @override
  bool operator ==(Object other) =>
      other is TempoSliceEntry && other.domain == domain && other.bpm == bpm;

  @override
  int get hashCode => Object.hash(domain, bpm);
}
