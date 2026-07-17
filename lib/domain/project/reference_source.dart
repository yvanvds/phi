import 'entity_address.dart';

/// An entity payload that points at other registry entities **by address** —
/// the opt-in hook that lets the registry keep its back-reference index and
/// refactor references on rename/move (design `docs/design/project-registry.md`
/// §4).
///
/// The registry core is kind-generic and treats a payload as an opaque
/// `Object?`, so it cannot know which addresses a clip, voice or mix bus points
/// at. A payload that *does* reference others implements this interface; the
/// registry then reads [references] to feed the index and calls
/// [withReferenceUpdated] to rewrite a reference when its target is renamed or
/// moved. A payload that references nothing simply doesn't implement it — the
/// entity then falls back to the reference set declared at creation
/// (`ProjectRegistry.createEntity(..., references: …)`), which is how
/// pre-migration entities (whose payloads are still plain domain objects)
/// participate.
///
/// **Structural vs textual.** A structured payload (a voice with
/// `output: mix.perc`) swaps one address field. A future `code.` block —
/// deferred to the live-coding epic — implements the very same contract with a
/// *textual* substitution over its source (`kind.old_name` → `kind.new_name`),
/// so the refactor machinery here does not preclude it.
abstract interface class ReferenceSource {
  /// The addresses this payload currently points at. May be empty. The registry
  /// treats this as authoritative for an entity whose payload is a
  /// [ReferenceSource], recomputing it whenever the payload is rewritten.
  Set<EntityAddress> get references;

  /// Returns a copy of this payload with every reference to [from] repointed to
  /// [to] — the refactor step a rename/move triggers for each referent.
  ///
  /// The result is itself a [ReferenceSource] whose [references] reflect the
  /// swap. Applying the inverse ([to] → [from]) must restore the original for
  /// undo to round-trip; a plain address substitution satisfies this.
  ReferenceSource withReferenceUpdated(EntityAddress from, EntityAddress to);
}
