import 'patch_connection.dart';
import 'patch_object_spec.dart';
import 'patch_point.dart';

/// The incremental-mutation seam the patcher gesture commands drive — the
/// pure-domain port the engine's per-entity patcher gateway implements (design
/// `docs/design/patcher.md` §3, §8; the real implementation is epic issue 2).
///
/// The design keeps **no parallel Phi-side graph model**: a patch's content
/// lives in the engine, and the persisted payload is that engine's `dumpJson`
/// (refreshed on save). Edits are therefore not applied to a Dart graph but
/// *forwarded* through this seam as gestures — add an object, connect two,
/// move one — each wrapped by an undoable `ProjectCommand` whose `revert`
/// forwards the inverse gesture. Every command binds one of these at
/// construction, exactly as the registry commands bind a `ProjectRegistry`.
///
/// The read methods ([describe], [connectionsOf], [positionOf], [paramOf]) let
/// a destructive gesture capture the state it must restore, so its undo is
/// exact. Handle ids are the engine's own — a create returns one, and
/// [restoreObject] recreates a deleted object under the *same* id so cables and
/// later gestures that named it stay valid through an undo/redo cycle.
abstract interface class PatchEditGateway {
  /// Creates an object from [spec] and returns the handle id assigned to it.
  int createObject(PatchObjectSpec spec);

  /// Recreates a previously-removed object under the exact [id] it held before,
  /// seeded from [spec] — the delete gesture's undo, and an add gesture's redo.
  void restoreObject(int id, PatchObjectSpec spec);

  /// Removes the object at [id] together with every cable touching it.
  void removeObject(int id);

  /// The full [PatchObjectSpec] of the object at [id] — its type, args, current
  /// position and params — read so a delete can restore it.
  PatchObjectSpec describe(int id);

  /// The connections touching the object at [id] (as source or destination) —
  /// read so a delete can re-wire them on undo.
  List<PatchConnection> connectionsOf(int id);

  /// Wires [connection] into the graph.
  void connect(PatchConnection connection);

  /// Removes [connection] from the graph.
  void disconnect(PatchConnection connection);

  /// Moves the object at [id] to [position].
  void moveObject(int id, PatchPoint position);

  /// The current position of the object at [id].
  PatchPoint positionOf(int id);

  /// Sets creation parameter [name] of the object at [id] to [value].
  void setParam(int id, String name, double value);

  /// The current value of parameter [name] on the object at [id], or `null`
  /// when the object never carried that parameter.
  double? paramOf(int id, String name);

  /// Removes parameter [name] from the object at [id] — the inverse of a
  /// [setParam] that first introduced the key, so a param edit's undo can strip
  /// a value that had no prior state.
  void clearParam(int id, String name);
}
