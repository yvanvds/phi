import '../../domain/project/entity_address.dart';

/// One placeable mix bus offered in the patcher's source-placement picker
/// (issue #224, design `docs/design/patcher.md` §4 role 1).
///
/// The patcher entity strip renders a `PhiSelect` over these so a patch can be
/// mounted as a `Sound` on any bus: the master bus, a user strip, a group bus,
/// or a return. The [address] is what `PatchPayload.placement` stores and what
/// the reconciler resolves to a live channel id; the [label] is the readable
/// name shown in the picker.
class PatchBusOption {
  const PatchBusOption({required this.address, required this.label});

  /// The `mix.` bus address this option places a patch onto.
  final EntityAddress address;

  /// The human-readable bus name shown in the picker.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is PatchBusOption &&
      other.address == address &&
      other.label == label;

  @override
  int get hashCode => Object.hash(address, label);
}
