import '../../domain/project/entity_address.dart';

/// A non-blocking notice raised when a `patch.` source placement cannot be
/// honoured (design `docs/design/patcher.md` §4, §8; issue #220).
///
/// A patch's placement bus is a *soft* pointer: when the reconciler tries to
/// mount (or keep mounted) a patcher on a bus that no longer exists, it leaves
/// the patch unplaced and raises one of these so the shell can surface a passing
/// message — the same graceful-degradation shape as [AudioDeviceNotice]. A pure
/// value type: no FFI, no Flutter, carried out of the engine to whichever surface
/// shows it.
class PatchPlacementNotice {
  /// Builds a notice for the patch at [patch] whose placement [bus] could not be
  /// resolved, with a human-readable [message] safe to show.
  const PatchPlacementNotice({
    required this.patch,
    required this.bus,
    required this.message,
  });

  /// The `patch.` entity whose source placement was dropped.
  final EntityAddress patch;

  /// The `mix.` bus the placement named — absent from the live mix, hence the
  /// notice.
  final EntityAddress bus;

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
  String toString() => 'PatchPlacementNotice($patch on $bus: $message)';
}
