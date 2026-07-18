import '../project/entity_address.dart';
import '../project/project_registry.dart';
import '../project/registry_kinds.dart';
import 'mix_strip.dart';

/// Validates the destination of an aux send at edit time (design
/// `docs/design/mix.md` §4): a send may only target a **return bus** — a
/// top-level `mix.` entity carrying `return: true`.
///
/// The engine rejects an illegal wiring by construction (a logged no-op), but the
/// domain refuses it first so the UI never offers a bad target and a bad send
/// never reaches the journal. Group buses are never returns (returns live outside
/// the tree, §4), so a group address — like any non-return, non-mix, or missing
/// address — is rejected.
abstract final class SendTarget {
  /// Whether [target] names a legal send destination in [registry]: a top-level
  /// `mix.` **entity** whose payload marks it a return. A plain strip, a group
  /// bus, a nested address, a non-`mix.` entity, or a missing address all yield
  /// `false`.
  static bool isReturn(ProjectRegistry registry, EntityAddress target) {
    if (target.kind != RegistryKinds.mix) return false;
    if (!target.isTopLevel) return false; // returns live only at top level
    final entity = registry.entityAt(target);
    if (entity == null) return false;
    final payload = entity.payload;
    final strip = payload is MixStrip
        ? payload
        : payload is Map
        ? MixStrip.fromJson(payload.cast<String, Object?>())
        : null;
    return strip?.isReturn ?? false;
  }

  /// Throws an [ArgumentError] when [target] is not a return bus in [registry],
  /// otherwise returns normally — the guard a send edit runs before it builds its
  /// payload command.
  static void validate(ProjectRegistry registry, EntityAddress target) {
    if (!isReturn(registry, target)) {
      throw ArgumentError.value(
        target.format(),
        'target',
        'a send target must be a top-level mix return bus',
      );
    }
  }
}
