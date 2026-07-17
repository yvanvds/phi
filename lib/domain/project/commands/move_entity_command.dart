import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Moves (or renames) the node at [from] to [to]; [revert] moves it back. A
/// rename is just a move whose leaf name changes, and a regroup a move whose
/// group path changes (design §4) — one command covers both.
class MoveEntityCommand implements ProjectCommand {
  MoveEntityCommand(this.registry, this.from, this.to);

  final ProjectRegistry registry;
  final EntityAddress from;
  final EntityAddress to;

  @override
  String get label => 'move $from → $to';

  @override
  Set<EntityAddress> get entitiesTouched => {from, to};

  @override
  void apply() => registry.move(from, to);

  @override
  void revert() => registry.move(to, from);

  @override
  Map<String, Object?> toJson() => {
    'type': 'move',
    'from': from.format(),
    'to': to.format(),
  };
}
