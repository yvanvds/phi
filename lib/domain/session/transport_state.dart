/// High-level transport state for the session.
///
/// Phi has no master clock by design, so "playing" is not "audio is rolling"
/// — it represents performer intent. The state machine surface (future) will
/// be the system of record for what each state *means* at audio level. For
/// now this is pure UI state.
enum TransportState { idle, playing }
