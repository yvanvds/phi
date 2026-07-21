import '../../domain/project/entity_address.dart';
import 'registry_mirror.dart';

/// The production [RegistryMirror] until the live-coding epic — every
/// notification is deliberately dropped (design §8). Wiring the registry to a
/// live mirror is that epic's job; until then the seam is proven present and
/// no-op by tests, and swapping in a real implementation touches nothing but
/// this binding.
class NoOpRegistryMirror implements RegistryMirror {
  /// A const, shareable no-op — the default the engine wires in production.
  const NoOpRegistryMirror();

  @override
  void onCreate(EntityAddress address) {}

  @override
  void onRename(EntityAddress from, EntityAddress to) {}

  @override
  void onRegroup(EntityAddress from, EntityAddress to) {}

  @override
  void onDelete(EntityAddress address) {}

  @override
  void syncAll(Iterable<EntityAddress> addresses) {}
}
