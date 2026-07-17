/// What the performer chose when asked about closing a project with unsaved
/// changes (design `docs/design/project-registry.md` §9, confirm-on-close).
enum CloseDecision {
  /// Save the pending changes, then close.
  save,

  /// Discard the pending changes and close anyway.
  discard,

  /// Stay open — abort the close.
  cancel,
}
