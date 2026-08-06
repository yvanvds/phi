import 'dart:ui';

import 'patch_object_descriptor.dart';
import 'patcher_graph_snapshot.dart';
import 'patcher_node_snapshot.dart';

/// Abstract port over `package:yse`'s `Patcher` + `Sound.fromPatcher`.
///
/// `PatcherController` depends on this interface, not on `package:yse`
/// directly, so tests can swap in a fake and the production code is the
/// only place the FFI surface is touched. See `real_patcher_gateway.dart`
/// for the production implementation.
///
/// **Multi-instance.** One engine `Patcher` is created per open `patch.`
/// entity (design `docs/design/patcher.md` §8). Every op is keyed by the
/// [int] instance id [createInstance] hands out, so ops on one instance
/// never touch another. Object handle ids are only unique *within* their
/// instance — always pass the instance that minted a handle.
abstract interface class PatcherGateway {
  // ─── instance lifecycle ──────────────────────────────────────────────

  /// Create a native patcher instance with [mainOutputs] audio output
  /// channels and return the id that keys every subsequent op.
  ///
  /// [name] is the **engine-direct bus name** the instance registers under —
  /// the kind-stripped `patch.` entity address (e.g. `fx.swirl` for
  /// `patch.fx.swirl`), so it is reachable at `patcher.<name>.<slot>` and the
  /// live-coding `patch.<name>.send(slot, v)` verb lands on it engine-side with
  /// no host round-trip (issue #318, design `docs/design/patcher.md`). The empty
  /// string (the default) creates an **anonymous** instance that is not
  /// bus-addressable.
  int createInstance({int mainOutputs = 2, String name = ''});

  /// Dispose one instance, tearing down its native patcher and any mounted
  /// [Sound] first. No-op for an unknown id.
  void disposeInstance(int instanceId);

  /// Dispose every instance — full subsystem teardown.
  void disposeAll();

  // ─── object lifecycle ────────────────────────────────────────────────

  /// Add an object of [type] (one of `package:yse`'s `Obj.*` constants) to
  /// [instanceId]. Returns the native handle id assigned by that patcher.
  int createObject(int instanceId, String type, {String args = ''});

  /// Remove a previously-created object. No-op for an unknown id.
  void deleteObject(int instanceId, int handleId);

  // ─── topology ────────────────────────────────────────────────────────

  /// Connect [fromHandleId]'s [outlet] to [toHandleId]'s [inlet].
  void connect(
    int instanceId, {
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  });

  /// Remove a connection previously made with [connect].
  void disconnect(
    int instanceId, {
    required int fromHandleId,
    required int outlet,
    required int toHandleId,
    required int inlet,
  });

  /// Inspect a node's port topology (counts + audio/control kinds).
  PatcherNodeSnapshot inspect(int instanceId, int handleId);

  /// Enumerate the whole live graph of [instanceId] — every object (its handle
  /// id, type, args, stored position, and port topology) and every connection.
  ///
  /// The seam that lets the editor **rebuild its canvas from a reloaded dump**
  /// (issue #308): after the reconciler `parseJson`s a patch's dump into a fresh
  /// native instance, the object handles, types, args and positions are all in
  /// the engine (positions ride in GUI properties) but the editor's Dart-side
  /// mirror is empty — this call reads them back so the mirror can be
  /// reconstructed. Returns [PatcherGraphSnapshot.empty] for an empty patcher.
  PatcherGraphSnapshot enumerate(int instanceId);

  // ─── canvas state, persisted to native via GUI properties ────────────

  /// Persist a node's `(x, y)` to the native object's GUI properties so a
  /// `dumpJson` round-trip preserves layout.
  void setNodePosition(int instanceId, int handleId, Offset position);

  /// Read back the position previously written by [setNodePosition].
  /// Returns null if either coordinate is missing or malformed.
  Offset? getNodePosition(int instanceId, int handleId);

  // ─── data flow (live GUI bodies) ─────────────────────────────────────

  /// Drop a float into [inlet] of [handleId]. Used by control-node bodies
  /// (`.slider`, `.f`, …) to push their value into the graph.
  void sendFloat(int instanceId, int handleId, int inlet, double value);

  /// Drop an integer into [inlet] of [handleId]. Used by control-node bodies
  /// whose engine object registers an **int** handler on the inlet but no
  /// float one — `.t` (gToggle) is the canonical case. The engine's inlet
  /// dispatch never coerces: a float sent at an int-only inlet is silently
  /// dropped, so pushing a toggle's state as a float reached nothing at all
  /// (issue #439).
  void sendInt(int instanceId, int handleId, int inlet, int value);

  /// Bang [inlet] of [handleId]. Used by control-node bodies (`.b`,
  /// message) to fire their trigger into the graph.
  void sendBang(int instanceId, int handleId, int inlet);

  /// The object's live GUI display value (yse's `guiValue`) — what a control
  /// body renders (a slider's position, a number's value, a toggle's on/off).
  /// The empty string for an object that has no display value or an unknown
  /// handle.
  String guiValue(int instanceId, int handleId);

  // ─── creation parameters (the metadata-driven params dialog) ─────────

  /// Reconfigure [handleId] with a new whitespace-joined creation-argument
  /// string (yse's `setParams`) — the params dialog applies documented
  /// creation parameters this way (design `docs/design/patcher.md` §7).
  void setParams(int instanceId, int handleId, String args);

  // ─── control I/O (the live-code seam) ────────────────────────────────

  /// Send a bang to the named `.r` receiver in [instanceId]. Returns
  /// whether such a receiver exists.
  bool passBang(int instanceId, String to);

  /// Send an integer to a named receiver. Returns whether it exists.
  bool passInt(int instanceId, int value, String to);

  /// Send a float to a named receiver. Returns whether it exists.
  bool passFloat(int instanceId, double value, String to);

  /// Send a string to a named receiver. Returns whether it exists.
  bool passString(int instanceId, String value, String to);

  // ─── source placement ────────────────────────────────────────────────

  /// Mount [instanceId]'s output as a [Sound] on the mix bus identified by
  /// [busChannelId] (the opaque id `YseGateway.createChannel` hands out;
  /// `null` routes to the master bus) so audio is heard — any bus, not just
  /// master. Idempotent per bus: re-calling with a *different* bus unmounts
  /// and re-mounts, so a placement change follows.
  void mountAsSource(int instanceId, {int? busChannelId, double volume = 1.0});

  /// Remove [instanceId]'s mounted [Sound], if any. No-op when unmounted.
  void unmountSource(int instanceId);

  // ─── persistence ─────────────────────────────────────────────────────

  String dumpJson(int instanceId);
  void parseJson(int instanceId, String content);

  // ─── metadata passthrough (process-wide registry) ────────────────────

  /// The engine's full object catalogue as FFI-free descriptors — the
  /// palette and reference panel read only this. The `patcher` (subpatch)
  /// type is filtered out (design §10 decision 2). Registry order.
  List<PatchObjectDescriptor> objectTypes();
}
