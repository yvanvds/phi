import 'materialised_fx.dart';

/// A mix bus's ordered insert-effect chain — the linked `DspObject` chain a
/// bus's `inserts` list materialises to (design `docs/design/racks-and-voices.md`
/// §5), placed pre-fader via `Channel.dsp`.
///
/// Minted by [FxGateway.createChain] bound to one mix bus. The owner (the
/// session layer, issue #208) drives it by handing the ordered set of
/// [MaterialisedFx] the bus's `inserts` resolve to:
///
/// - [setInserts] (re)links the placeable handles head-to-tail in the given
///   order and attaches the head to the bus — so **build** is the first call,
///   **reorder** is a later call with the same handles in a new order, and
///   **detach** is a call with an empty list. It never leaks: the handles are
///   *borrowed* (never disposed here), and re-linking overwrites every prior
///   link so no stale edge survives (see [FxGateway] for the terminator that
///   keeps a reorder acyclic under the current wrapper).
/// - [dispose] detaches from the bus and frees the chain's own resources; the
///   borrowed [MaterialisedFx] handles are the owner's to dispose.
///
/// yse-free so the boundary holds and a fake stands in for tests.
abstract interface class FxChain {
  /// The mix-bus channel id this chain places its head on — the opaque id
  /// `YseGateway.createChannel` hands out (or the master bus for the default).
  int get busChannelId;

  /// The placeable handles currently linked on the bus, in processing order —
  /// an unmodifiable view. Non-placeable handles ([MaterialisedFx.isPlaceable]
  /// `false`, i.e. a reserved `patcherInsert`) passed to [setInserts] are
  /// skipped and do not appear here.
  List<MaterialisedFx> get inserts;

  /// (Re)place the chain: link every placeable handle in [ordered] head-to-tail
  /// and attach the head to the bus, replacing any previous placement. An empty
  /// [ordered] (or one with no placeable handles) detaches the chain from the
  /// bus. The handles are borrowed — never disposed here.
  void setInserts(List<MaterialisedFx> ordered);

  /// Detach the chain from the bus and free the chain's own engine resources.
  /// Idempotent. Does **not** dispose the borrowed [MaterialisedFx] handles.
  void dispose();
}
