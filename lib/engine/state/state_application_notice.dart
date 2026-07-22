import '../../domain/project/entity_address.dart';

/// A non-blocking notice raised when entering a state could not apply
/// everything it captured (design `docs/design/state-graph.md` §4, issue
/// #243).
///
/// Slice entries and the on-enter script are *soft* pointers: a deleted
/// referent, an undefined variable, a clip with no decodable document, a
/// missing `code.` entity or a failed evaluation all degrade gracefully — the
/// rest of the state applies and one of these is raised so the performer sees
/// what was skipped. The same graceful-degradation shape as
/// [PatchPlacementNotice]: a pure value type, no FFI, no Flutter.
class StateApplicationNotice {
  /// Builds a notice for the entered [state] with a human-readable [message]
  /// describing the degradation that was applied.
  const StateApplicationNotice({required this.state, required this.message});

  /// The `state.` entity whose entry degraded.
  final EntityAddress state;

  /// A short, human-readable description of what was skipped or failed.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is StateApplicationNotice &&
      other.state == state &&
      other.message == message;

  @override
  int get hashCode => Object.hash(state, message);

  @override
  String toString() => 'StateApplicationNotice($state: $message)';
}
