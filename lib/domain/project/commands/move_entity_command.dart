import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Moves (or renames) the node at [from] to [to]; [revert] moves it back. A
/// rename is just a move whose leaf name changes, and a regroup a move whose
/// group path changes (design §4) — one command covers both.
///
/// **Rename = refactor.** The registry rewrites every referent to follow the
/// new address as part of the move, so this single command captures the whole
/// refactor and undoing it restores every rewritten reference. Those referents
/// join [entitiesTouched] (captured on [apply]) so save/autosave dirty-tracking
/// (#121) writes them too, not just the two endpoints.
class MoveEntityCommand implements ProjectCommand {
  MoveEntityCommand(this.registry, this.from, this.to);

  final ProjectRegistry registry;
  final EntityAddress from;
  final EntityAddress to;

  Set<EntityAddress> _rewritten = const {};

  @override
  String get label => 'move $from → $to';

  @override
  Set<EntityAddress> get entitiesTouched => {from, to, ..._rewritten};

  @override
  void apply() => _rewritten = registry.move(from, to);

  @override
  void revert() => registry.move(to, from);

  @override
  Map<String, Object?> toJson() => {
    'type': 'move',
    'from': from.format(),
    'to': to.format(),
  };
}
