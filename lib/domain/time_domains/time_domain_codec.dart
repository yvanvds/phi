import '../project/store/entity_payload_codec.dart';
import 'time_domain.dart';

/// The per-kind [EntityPayloadCodec] for `domain.` entities (design
/// `docs/design/project-registry.md` §5) — the migration of `TimeDomainRegistry`
/// into the registry's `domain.` namespace (review decision §12.1: a time domain
/// is "nearly a registry namespace already").
///
/// A [TimeDomain] is just a named tempo reference. The name is stored in the
/// payload alongside the [TimeDomain.tempo] so [decode] rebuilds a complete
/// value type without needing the entity address (the display name may differ
/// from the slugged address). Stamped at schema [version] `1`.
class TimeDomainCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const TimeDomainCodec();

  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    final domain = payload as TimeDomain;
    return <String, Object?>{'name': domain.name, 'tempo': domain.tempo};
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    final map = json as Map<String, Object?>;
    return TimeDomain(
      name: map['name'] as String? ?? 'domain',
      tempo: (map['tempo'] as num?)?.toDouble() ?? 120,
    );
  }
}
