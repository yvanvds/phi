import '../../domain/project/entity_address.dart';

/// Seam that mirrors registry lifecycle changes into the engine's embedded
/// Python namespace (design `docs/design/project-registry.md` §8) — so live
/// code can address `clip.drums`, `mix.perc`, … the moment they exist.
///
/// **No-op until the live-coding epic.** The interface and its wiring land now
/// (see `NoOpRegistryMirror`, the production implementation) so the registry
/// already pushes create / rename / delete / regroup notifications through a
/// stable seam; the epic swaps in an implementation that talks to the Python
/// runtime without re-plumbing the registry internals. Finding, 2026-07-16: the
/// engine's `yse` module is bus-primitives-only today — the Python object table
/// is new work on `yse-soundengine` / `dart-yse`, filed when the epic starts.
///
/// A `RegistryMirrorBinder` adapts the registry's neutral event stream onto
/// this interface, classifying a move into [onRename] (same parent group) or
/// [onRegroup] (a new parent) — the two distinctions the design calls out, and
/// snapshots the whole tree through [syncAll].
abstract interface class RegistryMirror {
  /// A new entity or group appeared at [address].
  void onCreate(EntityAddress address);

  /// The node at [from] was renamed in place — same parent group — to [to].
  void onRename(EntityAddress from, EntityAddress to);

  /// The node at [from] was moved to a different parent group, landing at [to].
  void onRegroup(EntityAddress from, EntityAddress to);

  /// The node at [address] — and, for a group, its subtree — was removed.
  void onDelete(EntityAddress address);

  /// Replace the mirror's whole view with exactly [addresses] — every group and
  /// entity currently in the registry, parents before children.
  ///
  /// This is the **full-sync** path the live-coding epic drives at two moments
  /// (design `docs/design/live-coding.md` §3): the **boot sync** right after the
  /// `phi` library is bootstrapped into a fresh interpreter, and the
  /// **re-init re-sync** after a `System` close/init blanks that interpreter —
  /// the mirror must notice the table went empty and re-push everything. Unlike
  /// the incremental [onCreate]/[onDelete] events, a full sync is idempotent, so
  /// re-running it can only converge the interpreter onto the current tree.
  void syncAll(Iterable<EntityAddress> addresses);
}
