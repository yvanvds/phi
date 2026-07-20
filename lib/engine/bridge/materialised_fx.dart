import '../../domain/fx/fx_definition.dart';
import '../../domain/fx/fx_kind.dart';

/// A live engine effect materialised from an `fx.` definition — the handle a
/// mix bus's insert chain places (design `docs/design/racks-and-voices.md` §5).
///
/// Minted by [FxGateway.materialiseFx], which builds the matching engine
/// `DspObject` for the definition's [FxKind] and applies its params. The handle
/// then lets its owner:
///
/// - **re-apply** an edited definition ([applyDefinition]) — every yse
///   `DspObject`/`Compressor` setter is click-free (ramped where the engine
///   ramps), so a same-kind param edit is glitch-free; a kind change rebuilds
///   the underlying object, after which the owning [FxChain] must re-place
///   (its `dspObject` identity changed, mirroring a synth pool rebuild);
/// - **dispose** it, freeing the engine effect. The chain only *borrows* the
///   handle, so an instance outlives its placement and is disposed once, by the
///   owner, when the `fx.` entity is removed (issue #208).
///
/// The interface is yse-free so the engine-bridge boundary holds and a fake can
/// stand in for the whole surface in tests. This handle is a *primitive*;
/// resolving which bus an instance sits on (its `inserts` back-reference) and
/// re-applying definition edits across every placement is the session layer's
/// job (issue #208).
abstract interface class MaterialisedFx {
  /// Which effect kind this handle was built from — follows [definition].
  FxKind get kind;

  /// The definition currently applied — the last value handed to the
  /// constructor or [applyDefinition].
  FxDefinition get definition;

  /// Whether this handle carries a real engine effect that an [FxChain] can
  /// place. `false` only for [FxKind.patcherInsert], which is reserved but not
  /// wired until the patcher epic (design §5) — a chain skips such handles so
  /// nothing re-plumbs when it lands.
  bool get isPlaceable;

  /// Re-apply [definition] to the live effect. A same-kind edit writes the
  /// changed params through click-free setters; a kind change rebuilds the
  /// underlying effect (the owning chain must re-place afterwards).
  void applyDefinition(FxDefinition definition);

  /// Release the engine effect. Idempotent. The owner disposes the handle; a
  /// chain that placed it must drop it from its order first (or the borrowed
  /// pointer dangles).
  void dispose();
}
