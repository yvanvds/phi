/// What a [PerformanceState] captures when it becomes live: the time
/// domains, code blocks, and scene pose pointer it should swap in.
///
/// All three fields are placeholders — the authoring layers
/// (time-domains, scripting, scene-pose) don't ship until later phases,
/// so today the snapshot is read-only with empty defaults. The right
/// inspector still renders the three labelled sections so the contract
/// stays visible.
///
/// Immutable. Replace via [copyWith].
class StateSnapshot {
  const StateSnapshot({
    this.domainIds = const [],
    this.codeBlockIds = const [],
    this.sceneRef,
  });

  /// The empty snapshot — every new [PerformanceState] starts here.
  static const StateSnapshot empty = StateSnapshot();

  /// Time-domain identifiers this state activates. Pointers into the
  /// time-domain layer (issue #6).
  final List<String> domainIds;

  /// Live-coding block identifiers this state pins. Pointers into the
  /// scripting layer (issue #9 onwards).
  final List<String> codeBlockIds;

  /// Scene-pose reference (camera + agent positions) this state loads.
  /// Free-form string for now — formalises once the scene snapshot type
  /// lands.
  final String? sceneRef;

  StateSnapshot copyWith({
    List<String>? domainIds,
    List<String>? codeBlockIds,
    String? sceneRef,
    bool clearSceneRef = false,
  }) => StateSnapshot(
    domainIds: domainIds ?? this.domainIds,
    codeBlockIds: codeBlockIds ?? this.codeBlockIds,
    sceneRef: clearSceneRef ? null : (sceneRef ?? this.sceneRef),
  );
}
