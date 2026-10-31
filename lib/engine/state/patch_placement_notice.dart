import '../../domain/project/entity_address.dart';

/// A non-blocking notice raised when a `patch.` entity cannot be honoured as
/// written (design `docs/design/patcher.md` §4, §8; issues #220, #452).
///
/// Two degradations raise one: a source placement naming a bus that no longer
/// exists (the patch is left unplaced — [bus] names the missing bus), and a
/// patch whose address is too long for the engine to register its native
/// patcher by name (it opens anonymous, so `patcher.<name>.<slot>` does not
/// reach it — [bus] is `null`). Either way the reconciler degrades and raises
/// this so the shell can surface a passing message — the same
/// graceful-degradation shape as [AudioDeviceNotice]. A pure value type: no
/// FFI, no Flutter, carried out of the engine to whichever surface shows it.
class PatchPlacementNotice {
  /// Builds a notice for the patch at [patch], with a human-readable [message]
  /// safe to show. [bus] is the unresolvable placement bus, when the notice is
  /// about placement.
  const PatchPlacementNotice({
    required this.patch,
    this.bus,
    required this.message,
  });

  /// The `patch.` entity the notice is about.
  final EntityAddress patch;

  /// The `mix.` bus the placement named — absent from the live mix, hence the
  /// notice — or `null` when the notice is not about placement.
  final EntityAddress? bus;

  /// A short, human-readable description of the degradation that was applied.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is PatchPlacementNotice &&
      other.patch == patch &&
      other.bus == bus &&
      other.message == message;

  @override
  int get hashCode => Object.hash(patch, bus, message);

  @override
  String toString() => bus == null
      ? 'PatchPlacementNotice($patch: $message)'
      : 'PatchPlacementNotice($patch on $bus: $message)';
}
