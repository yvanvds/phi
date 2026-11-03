import '../project/entity_address.dart';
import '../project/registry_kinds.dart';

/// The vocabulary of **abstractions** (issue #553): one `patch.` entity used as
/// the definition of any number of subpatch boxes, in any number of patches.
///
/// A box is an **instance** of a definition when its name — the arguments of
/// its `patcher` object — is the definition's address: `patcher patch.gain`
/// reads the way Max's `gain` does, and what the box says is all there is. So a
/// reference travels through a duplicate, a paste, an undo and a save with no
/// machinery of its own, and giving the box any other name makes it an ordinary
/// subpatch again (design `docs/design/patcher.md` §13).
///
/// Pure Dart: the rule about a string, for the editor, the sync and the tests.
abstract final class PatchAbstraction {
  /// The definition [args] name, or null when they are an ordinary name: not
  /// one word, not a well-formed address, or an address of another kind.
  static EntityAddress? referenceIn(String args) {
    final trimmed = args.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
    final address = EntityAddress.tryParse(trimmed);
    return address?.kind == RegistryKinds.patch ? address : null;
  }

  /// Where [reference] points once the node at [from] has moved to [to]:
  /// following a rename of the definition itself or of a group around it.
  static EntityAddress moved(
    EntityAddress reference,
    EntityAddress from,
    EntityAddress to,
  ) {
    if (reference == from) return to;
    if (!reference.isDescendantOf(from)) return reference;
    return EntityAddress(
      kind: to.kind,
      segments: [
        ...to.segments,
        ...reference.segments.skip(from.segments.length),
      ],
    );
  }

  /// The type id the object box and the palette offer a definition under: its
  /// address, which is what a person types. It is not an engine type; the editor
  /// turns it into a `patcher` box named after the address ([referenceIn] is the
  /// same rule read the other way).
  static String typeOf(EntityAddress definition) => definition.format();

  /// The definition a catalogue [type] id stands for, or null for an engine
  /// type. Engine type ids never parse: they start with `~` or `.`, or are bare.
  static EntityAddress? addressOfType(String type) => referenceIn(type);
}
