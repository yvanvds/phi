import '../commands/create_entity_command.dart';
import '../commands/create_group_command.dart';
import '../commands/move_entity_command.dart';
import '../commands/remove_entity_command.dart';
import '../commands/update_entity_payload_command.dart';
import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Reconstructs a registry [ProjectCommand] from the JSON a command's `toJson`
/// wrote to the journal — the read side of crash recovery (design
/// `docs/design/project-registry.md` §7).
///
/// Recovery is **domain-only replay**: each journal line is decoded back into a
/// command bound to the recovered [ProjectRegistry] and re-[ProjectCommand.apply]d
/// in order, so the pure-Dart tree ends up exactly as it was before the crash
/// (the engine is booted once from the final state, never during replay). This
/// codec is the inverse of the four registry commands' `toJson`; it is
/// deliberately forward-only — replay never calls `revert`, so a decoded
/// command needs no apply-time captured state.
///
/// The fine-grained clip-editor commands are *not* journaled directly (they
/// target a `MidiClip`, not the registry). Instead, a clip edit publishes its
/// new interpretation as an `update_payload` registry command on the `clip.`
/// entity (issue #135), which this codec reconstructs like any other — so a
/// crash replays the clip's edited state without needing note-level replay.
class RegistryCommandCodec {
  /// A const codec — it holds no state.
  const RegistryCommandCodec();

  /// Decodes one journal entry ([json], a command's `toJson` map) into the
  /// command it recorded, bound to [registry] so replay mutates the recovered
  /// tree.
  ///
  /// Throws a [FormatException] when `type` is missing or names a command this
  /// codec does not know, so a corrupt or forward-incompatible journal fails
  /// loudly rather than silently dropping an edit.
  ProjectCommand decode(Map<String, Object?> json, ProjectRegistry registry) {
    final type = json['type'];
    switch (type) {
      case 'create_entity':
        return CreateEntityCommand(
          registry,
          _address(json, 'address'),
          payload: json['payload'],
          references: _references(json),
        );
      case 'create_group':
        return CreateGroupCommand(registry, _address(json, 'address'));
      case 'move':
        return MoveEntityCommand(
          registry,
          _address(json, 'from'),
          _address(json, 'to'),
        );
      case 'remove_entity':
        return RemoveEntityCommand(registry, _address(json, 'address'));
      case 'update_payload':
        return UpdateEntityPayloadCommand(
          registry,
          _address(json, 'address'),
          json['payload'],
        );
      default:
        throw FormatException('Unknown journal command type: "$type".');
    }
  }

  EntityAddress _address(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw is! String) {
      throw FormatException('Journal entry is missing string "$key": $json.');
    }
    return EntityAddress.parse(raw);
  }

  Set<EntityAddress> _references(Map<String, Object?> json) {
    final raw = json['references'];
    if (raw == null) return const {};
    if (raw is! List) {
      throw FormatException('Journal "references" must be a list: $raw.');
    }
    return {for (final r in raw) EntityAddress.parse(r as String)};
  }
}
