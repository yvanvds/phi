import 'time_domain.dart';

/// An immutable lookup of [TimeDomain]s keyed by name.
///
/// The lightweight resolution surface a `DomainSubscriptionTransform` (the
/// #32 follow-up) uses to turn a subscribed domain *name* into a concrete
/// [TimeDomain] to tempo-lock against. Pure Dart, no engine wiring — a
/// simple name→domain map behind a value-type façade.
///
/// Immutable: [add] and [remove] return new registries rather than mutating
/// in place, matching the copy-on-write house style. Names are unique;
/// [add] overrides any existing domain sharing a name.
class TimeDomainRegistry {
  /// Build a registry from [domains]. Later entries win when two share a
  /// name, so a caller can layer overrides onto defaults.
  TimeDomainRegistry([Iterable<TimeDomain> domains = const []])
    : _byName = Map.unmodifiable({for (final d in domains) d.name: d});

  const TimeDomainRegistry._(this._byName);

  final Map<String, TimeDomain> _byName;

  /// The registered domains, in insertion order. Treat as a set.
  Iterable<TimeDomain> get domains => _byName.values;

  /// The registered domain names.
  Iterable<String> get names => _byName.keys;

  /// How many domains are registered.
  int get length => _byName.length;

  /// Whether a domain named [name] is registered.
  bool contains(String name) => _byName.containsKey(name);

  /// The domain named [name], or `null` if none is registered.
  TimeDomain? resolve(String name) => _byName[name];

  /// A new registry with [domain] added (or replacing any domain sharing
  /// its name).
  TimeDomainRegistry add(TimeDomain domain) =>
      TimeDomainRegistry._(Map.unmodifiable({..._byName, domain.name: domain}));

  /// A new registry with the domain named [name] removed. Returns an equal
  /// registry when [name] is not present.
  TimeDomainRegistry remove(String name) {
    if (!_byName.containsKey(name)) return this;
    final next = Map<String, TimeDomain>.from(_byName)..remove(name);
    return TimeDomainRegistry._(Map.unmodifiable(next));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeDomainRegistry && _mapEquals(other._byName, _byName);

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final e in _byName.entries) Object.hash(e.key, e.value),
  ]);

  @override
  String toString() => 'TimeDomainRegistry(${_byName.values.join(', ')})';

  static bool _mapEquals(Map<String, TimeDomain> a, Map<String, TimeDomain> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
