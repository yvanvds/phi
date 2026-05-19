import 'dart:ui';

import 'patcher_node_snapshot.dart';

/// Abstract port over `package:yse`'s `Patcher` + `Sound.fromPatcher`.
///
/// `PatcherController` depends on this interface, not on `package:yse`
/// directly, so tests can swap in a fake and the production code is the
/// only place the FFI surface is touched. See `real_patcher_gateway.dart`
/// for the production implementation.
abstract interface class PatcherGateway {
  /// Create the native patcher and mount the obligatory `~dac` object.
  /// [mainOutputs] sets the audio output channel count.
  void init({int mainOutputs = 2});

  /// Tear the native patcher down. Disposes any mounted [Sound] first.
  void dispose();

  // ─── object lifecycle ────────────────────────────────────────────────

  /// Add an object of [type] (one of `package:yse`'s `Obj.*` constants).
  /// Returns the native handle id assigned by the patcher.
  int createObject(String type, {String args = ''});

  /// Remove a previously-created object. No-op for an unknown id.
  void deleteObject(int handleId);

  // ─── topology ────────────────────────────────────────────────────────

  /// Connect [fromHandleId]'s [outlet] to [toHandleId]'s [inlet].
  void connect({
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  });

  /// Remove a connection previously made with [connect].
  void disconnect({
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  });

  /// Inspect a node's port topology (counts + audio/control kinds).
  PatcherNodeSnapshot inspect(int handleId);

  // ─── canvas state, persisted to native via GUI properties ────────────

  /// Persist a node's `(x, y)` to the native object's GUI properties so a
  /// `dumpJson` round-trip preserves layout.
  void setNodePosition(int handleId, Offset position);

  /// Read back the position previously written by [setNodePosition].
  /// Returns null if either coordinate is missing or malformed.
  Offset? getNodePosition(int handleId);

  // ─── data flow ───────────────────────────────────────────────────────

  /// Drop a float into [inlet] of [handleId]. Used by control-node bodies
  /// (`.slider`, `.f`, …) to push their value into the graph.
  void sendFloat(int handleId, int inlet, double value);

  // ─── lifecycle ───────────────────────────────────────────────────────

  /// Attach this patcher's `~dac` output to a [Sound] routed to the
  /// master channel so audio is actually heard. Idempotent — calling
  /// twice replaces the previous mount.
  void mountAsSound({double volume = 1.0});

  // ─── persistence ─────────────────────────────────────────────────────

  String dumpJson();
  void parseJson(String content);
}
