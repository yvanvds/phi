/// The reason a [RegistryException] was thrown — the structured cause a caller
/// or test can branch on, independent of the exact wording.
enum RegistryError {
  /// A name failed [NameValidator] (bad shape, keyword, reserved, …).
  invalidName,

  /// A sibling with that name already exists, so the create/move would
  /// duplicate it (case-insensitive).
  duplicateName,

  /// A group and an entity would share a name at the same level, or an
  /// ancestor on the path exists as an entity where a group is needed.
  groupEntityClash,

  /// Nothing exists at the address the operation targeted.
  notFound,

  /// A move named a different [EntityAddress.kind] for source and destination;
  /// entities never cross namespaces.
  crossKindMove,

  /// A move would place a group inside its own subtree.
  moveIntoDescendant,
}
