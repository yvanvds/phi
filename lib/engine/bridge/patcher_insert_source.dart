import 'package:yse/yse.dart';

/// A source of live native patchers the fx gateway borrows to build
/// `DspObject.patcherInsert` insert effects (design `docs/design/patcher.md` §4
/// role 2, issue #225).
///
/// A patcher-insert `fx.` entity wraps a `patch.` reference; the engine
/// materialises it as a `DspObject.patcherInsert` that **borrows** the patch's
/// live native [Patcher]. That native patcher is owned by the patcher gateway
/// (one per open `patch.` entity), so the [RealFxGateway] resolves it through this
/// seam rather than owning it — keeping `package:yse` touched only inside the
/// bridge, and letting a test stand a fake in.
///
/// The `RealPatcherGateway` implements it: the fx gateway hands it the patcher
/// instance id the [PatchReconciler] resolved for a wrapped `patch.` entity, and
/// gets back the [Patcher] to borrow. The insert never owns or disposes the
/// patcher — it must outlive the insert (upstream contract), which the reconciler
/// guarantees by disposing a patch's native instance only after the chains that
/// borrow it have been detached.
abstract interface class PatcherInsertSource {
  /// The live native [Patcher] for [patchInstanceId], or `null` when no such
  /// instance exists (a stale / torn-down patch). The returned patcher is
  /// *borrowed* by `DspObject.patcherInsert`.
  Patcher? patcherFor(int patchInstanceId);
}
