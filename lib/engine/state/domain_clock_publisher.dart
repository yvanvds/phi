import '../../domain/project/entity_address.dart';
import '../bridge/patch_clock.dart';

/// Publishes one engine clock per Phi time domain, so a patch can follow the
/// domain by name (issue #529).
///
/// Patcher clock objects find an engine domain clock by name. Phi's time
/// domains are Dart-side tempo references whose engine clocks are minted per
/// use (one per clip session, the count-in, the click), so before this a patch
/// had nothing to bind to. The publisher keeps, for every `domain.` entity, a
/// clock named by the domain's address — `domain.drum` — paced at the domain's
/// played tempo.
///
/// The decisions behind it (recorded on issue #529):
///
/// - **Name:** the domain's documented address, `domain.<name>`, used verbatim
///   as the engine clock name ([clockNameFor]). No short form, so it can never
///   collide with a clock a patch names for itself (`song`, `drum`).
/// - **Tempo:** the domain's *played* tempo, as [tempoOf] reports it — the
///   authored tempo, a state's live override over it, bent by the tempo fader:
///   the rate a clip subscribed to the domain plays at. Pushed whenever it
///   changes ([sync]).
/// - **Ownership:** Phi's. The domain never reads the clock back, so a patch's
///   `.transport`, `.setclock` or `.tempo` writing it moves only the patch
///   objects on that clock, never the domain or its clips, and only until the
///   domain's tempo next changes. The engine has no read-only clock, so this is
///   a convention the docs state, not a lock.
/// - **Position:** the engine clock's own beat — beats counted since the clock
///   was published (the project opening, or the domain being created). It runs
///   whether or not Phi is playing; START does not start or reset it.
/// - **Lifetime:** the clock lives exactly as long as its domain. A removed
///   domain's clock is destroyed; objects still bound to it read a frozen beat.
///   [release] drops them all ahead of an audio-session restart or a stop, and
///   the next [sync] publishes them again.
///
/// A name a patch claimed first (a `.transport domain.drum` loaded before the
/// domain existed) cannot be taken over — the engine's first registration
/// wins — so that domain goes unpublished until the next [release].
class DomainClockPublisher {
  DomainClockPublisher({
    required this._publish,
    required this._domains,
    required this._tempoOf,
  });

  final PatchClock? Function(String name, double tempo) _publish;
  final Iterable<EntityAddress> Function() _domains;
  final double? Function(EntityAddress domain) _tempoOf;

  final Map<String, PatchClock> _clocks = {};
  final Map<String, double> _applied = {};
  final Set<String> _refused = {};

  /// The engine clock name a patch uses to follow [domain]: its address.
  static String clockNameFor(EntityAddress domain) => domain.format();

  /// The published clock following [domain], or `null` when it has none.
  PatchClock? clockOf(EntityAddress domain) => _clocks[clockNameFor(domain)];

  /// The names of every published clock.
  Iterable<String> get clockNames => _clocks.keys;

  /// Bring the published clocks in line with the domains: publish one for a
  /// new domain, destroy the one of a domain that is gone, and push the played
  /// tempo to any clock whose domain's tempo changed.
  void sync() {
    final desired = <String, double>{};
    for (final domain in _domains()) {
      final tempo = _tempoOf(domain);
      if (tempo != null && tempo > 0) desired[clockNameFor(domain)] = tempo;
    }
    for (final name in _clocks.keys.toList()) {
      if (desired.containsKey(name)) continue;
      _clocks.remove(name)!.dispose();
      _applied.remove(name);
    }
    _refused.removeWhere((name) => !desired.containsKey(name));
    for (final MapEntry(key: name, value: tempo) in desired.entries) {
      final clock = _clocks[name];
      if (clock != null) {
        if (_applied[name] != tempo) {
          clock.setTempo(tempo);
          _applied[name] = tempo;
        }
        continue;
      }
      if (_refused.contains(name)) continue;
      final published = _publish(name, tempo);
      if (published == null) {
        _refused.add(name);
        continue;
      }
      _clocks[name] = published;
      _applied[name] = tempo;
    }
  }

  /// Destroy every published clock — ahead of an audio-session restart or a
  /// stop, which close the engine session the clocks live in. The next [sync]
  /// publishes them again.
  void release() {
    for (final clock in _clocks.values) {
      clock.dispose();
    }
    _clocks.clear();
    _applied.clear();
    _refused.clear();
  }
}
