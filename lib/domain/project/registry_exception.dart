import 'registry_error.dart';

/// Thrown when a [ProjectRegistry] mutation would violate a tree invariant —
/// an invalid name, a duplicate or clashing sibling, a missing target, or an
/// illegal move.
///
/// Carries a structured [error] (what tests and callers branch on) and a
/// human-readable [message] (what a dialog shows). Queries never throw; only
/// `create` / `move` / `remove`-style mutations do.
class RegistryException implements Exception {
  const RegistryException(this.error, this.message);

  /// The structured cause.
  final RegistryError error;

  /// A short, user-facing explanation.
  final String message;

  @override
  String toString() => 'RegistryException(${error.name}): $message';
}
