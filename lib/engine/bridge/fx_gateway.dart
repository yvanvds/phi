import '../../domain/fx/fx_definition.dart';
import 'fx_chain.dart';
import 'materialised_fx.dart';

/// Abstract port over `package:yse`'s **effect** surface (design
/// `docs/design/racks-and-voices.md` §5) — the fx half of the racks epic.
///
/// Materialises an `fx.` definition into an engine `DspObject` and links a mix
/// bus's ordered `inserts` into a placed chain. Like [SynthGateway] and
/// [MidiGateway], the session/voice layer depends on this interface, not on
/// `package:yse`, so the real FFI surface is touched in exactly one place
/// (`real_fx_gateway.dart`) and a fake stands in for tests.
///
/// Two primitives:
///
/// - [materialiseFx] builds one [MaterialisedFx] handle per `fx.` instance
///   (the effect + its params), which then re-applies edits and disposes.
/// - [createChain] mints an [FxChain] bound to a mix bus that links those
///   handles in `inserts` order and places the head via `Channel.dsp`.
///
/// **Reorder under the current wrapper.** `Channel.dsp` + `DspObject.link` can
/// build and detach a chain, but the wrapper's `link` cannot clear a `next`
/// pointer (the native API accepts `NULL`; the Dart binding requires a
/// non-null object — filed **yvanvds/dart-yse#42**). A naive reorder would
/// therefore leave a stale edge and could close a cycle. The real chain sidesteps
/// this with a permanent bypassed **terminator** as the tail: every real object
/// is re-linked to its successor (the next insert or the terminator) on each
/// placement, so no stale edge survives and the walk always ends at the
/// terminator. Wiring a whole voice's fx (resolving the bus, re-applying a
/// definition across placements) is the session layer's job (issue #208).
abstract interface class FxGateway {
  /// Materialise the engine effect for [definition] and apply its params.
  /// Returns a [MaterialisedFx] handle carrying the rest of the lifecycle
  /// (re-application, disposal). Not yet placed on any bus — hand it to an
  /// [FxChain] for that.
  ///
  /// [patchInstanceId] is the live native patcher instance a
  /// [FxKind.patcherInsert] wraps (design `docs/design/patcher.md` §4 role 2,
  /// issue #225) — the id the [PatchReconciler] resolved for the definition's
  /// wrapped `patch.` entity. `null` for every other kind, and for a patcher
  /// insert whose patch is not (yet) materialised: the handle is then not
  /// placeable, so the chain skips it until a later re-sync resolves it.
  MaterialisedFx materialiseFx(FxDefinition definition, {int? patchInstanceId});

  /// Create an (initially empty) insert chain bound to the mix bus with id
  /// [busChannelId] — the opaque id `YseGateway.createChannel` hands out; the
  /// gateway's resolver maps an unknown id to the master bus. Drive it with
  /// [FxChain.setInserts].
  FxChain createChain({required int busChannelId});
}
