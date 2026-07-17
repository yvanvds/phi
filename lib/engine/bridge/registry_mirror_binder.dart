import 'dart:async';

import '../../domain/project/entity_address.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_event.dart';
import 'registry_mirror.dart';

/// Pumps a [ProjectRegistry]'s lifecycle events into a [RegistryMirror],
/// classifying each move into a rename or a regroup (design
/// `docs/design/project-registry.md` §8).
///
/// This is the one place that adapts the domain's neutral [RegistryEvent]
/// stream onto the mirror's create / rename / delete / regroup vocabulary, so
/// the mirror implementation stays free of registry details. [bind] follows the
/// active registry — call it again after a New/Open swaps the tree and the
/// previous subscription is dropped first, so exactly one registry is mirrored
/// at a time; [dispose] detaches for good.
class RegistryMirrorBinder {
  /// Wraps [_mirror]; nothing is observed until the first [bind].
  RegistryMirrorBinder(this._mirror);

  final RegistryMirror _mirror;
  StreamSubscription<RegistryEvent>? _subscription;
  ProjectRegistry? _boundRegistry;

  /// The registry currently observed, or `null` before the first [bind] and
  /// after [dispose].
  ProjectRegistry? get boundRegistry => _boundRegistry;

  /// Observe [registry], forwarding its events to the mirror. Idempotent when
  /// [registry] is already bound; otherwise the previous subscription is
  /// cancelled first.
  void bind(ProjectRegistry registry) {
    if (identical(registry, _boundRegistry)) return;
    _subscription?.cancel();
    _boundRegistry = registry;
    _subscription = registry.events.listen(_forward);
  }

  /// Stop mirroring and release the subscription.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _boundRegistry = null;
  }

  void _forward(RegistryEvent event) {
    switch (event) {
      case RegistryEntityCreated(:final address):
        _mirror.onCreate(address);
      case RegistryEntityDeleted(:final address):
        _mirror.onDelete(address);
      case RegistryEntityMoved(:final from, :final to):
        if (_sameParent(from, to)) {
          _mirror.onRename(from, to);
        } else {
          _mirror.onRegroup(from, to);
        }
    }
  }

  /// Whether [a] and [b] share a parent group — same kind, identical group path
  /// — the mark of a pure rename. Any group-path change is a regroup.
  static bool _sameParent(EntityAddress a, EntityAddress b) {
    if (a.kind != b.kind) return false;
    final ap = a.groupPath;
    final bp = b.groupPath;
    if (ap.length != bp.length) return false;
    for (var i = 0; i < ap.length; i++) {
      if (ap[i] != bp[i]) return false;
    }
    return true;
  }
}
