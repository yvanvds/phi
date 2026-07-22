import 'dart:ui';

import 'patcher_node_snapshot.dart';

/// One object read back from a live patcher instance by
/// [PatcherGateway.enumerate] — everything the editor needs to reconstruct a
/// `PatchNode` for a graph loaded from a dump (issue #308).
///
/// Carries the native [handleId], the object [type] and its creation [args]
/// (so a later save re-dumps it identically), the stored canvas [position]
/// (`null` when the object never had one written to its GUI properties), and
/// the port topology as a [PatcherNodeSnapshot] — the same shape
/// [PatcherGateway.inspect] hands back for a freshly-created object.
class PatcherObjectSnapshot {
  const PatcherObjectSnapshot({
    required this.handleId,
    required this.type,
    required this.args,
    required this.position,
    required this.ports,
  });

  /// The native handle id that keys every gateway op on this object.
  final int handleId;

  /// The object type identifier (one of `package:yse`'s `Obj.*` constants).
  final String type;

  /// The creation-argument string the object was made / last reconfigured with.
  final String args;

  /// The canvas position stored in the object's GUI properties, or `null` when
  /// none was ever written (the editor falls back to the origin).
  final Offset? position;

  /// The object's inlet / outlet topology (counts + audio/control kinds).
  final PatcherNodeSnapshot ports;
}

/// One connection read back from a live patcher instance by
/// [PatcherGateway.enumerate] — an outlet on one object wired to an inlet on
/// another, in native handle-id terms.
class PatcherConnectionSnapshot {
  const PatcherConnectionSnapshot({
    required this.fromHandleId,
    required this.outlet,
    required this.toHandleId,
    required this.inlet,
  });

  final int fromHandleId;
  final int outlet;
  final int toHandleId;
  final int inlet;
}

/// The full topology of a live patcher instance — every [objects] object and
/// every [connections] cable — as [PatcherGateway.enumerate] reports it.
///
/// The editor rebuilds its Dart-side `PatchGraph` mirror from this when a patch
/// is opened from a reloaded dump (or after a rename re-materialises its native
/// instance), so the canvas shows the loaded graph rather than an empty scene
/// (issue #308).
class PatcherGraphSnapshot {
  const PatcherGraphSnapshot({
    required this.objects,
    required this.connections,
  });

  /// An empty patcher — no objects, no cables.
  static const PatcherGraphSnapshot empty = PatcherGraphSnapshot(
    objects: [],
    connections: [],
  );

  final List<PatcherObjectSnapshot> objects;
  final List<PatcherConnectionSnapshot> connections;
}
