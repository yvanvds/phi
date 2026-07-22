/// The four v1 slice categories a `state.` entity captures independently
/// (design `docs/design/state-graph.md` §4, issue #242): the set of playing
/// clips, the mix levels per chosen bus, the runtime-variable values, and the
/// per-domain tempos.
///
/// Each category is present or absent on a state on its own — capture and
/// clear act per category, never on the whole world. The application order on
/// entry (#243) is fixed elsewhere (variables → tempos → mix → clips); this
/// enum is only the addressing scheme capture / clear / editing share. Scene
/// and voice-rebinding slices are deliberate future extensions (design §7).
enum StateSliceCategory {
  /// The set of playing clips (+ loop flags).
  clips,

  /// Volume/mute per chosen bus.
  mix,

  /// Runtime-variable values.
  variables,

  /// Per-domain tempos.
  tempos,
}
