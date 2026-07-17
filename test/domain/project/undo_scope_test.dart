import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/undo_scope.dart';

/// A minimal [ProjectCommand] over a shared log, so a scope's ordering and
/// apply/revert dispatch can be asserted without a real registry.
class _AppendCommand implements ProjectCommand {
  _AppendCommand(this.log, this.token);

  final List<String> log;
  final String token;

  @override
  String get label => 'append $token';

  @override
  Set<EntityAddress> get entitiesTouched => {
    EntityAddress.parse('clip.$token'),
  };

  @override
  void apply() => log.add(token);

  @override
  void revert() => log.removeLast();

  @override
  Map<String, Object?> toJson() => {'type': 'append', 'token': token};
}

void main() {
  late List<String> log;
  late UndoScope scope;
  var notifications = 0;

  setUp(() {
    log = [];
    scope = UndoScope(id: 'test');
    notifications = 0;
    scope.addListener(() => notifications++);
  });

  tearDown(() => scope.dispose());

  test('id defaults its label; an explicit label overrides', () {
    expect(UndoScope(id: 'midi').label, 'midi');
    expect(UndoScope(id: 'midi', label: 'MIDI editor').label, 'MIDI editor');
  });

  test('a fresh scope has nothing to undo or redo', () {
    expect(scope.canUndo, isFalse);
    expect(scope.canRedo, isFalse);
    expect(scope.lastCommand, isNull);
    expect(scope.lastEvent, isNull);
  });

  test('run applies the command, enables undo, and reports the event', () {
    scope.run(_AppendCommand(log, 'a'));
    expect(log, ['a']);
    expect(scope.canUndo, isTrue);
    expect(scope.canRedo, isFalse);
    expect(scope.lastEvent, UndoEvent.applied);
    expect(scope.lastCommand?.label, 'append a');
    expect(notifications, 1);
  });

  test('undo applies the inverse and moves the command to the redo stack', () {
    scope.run(_AppendCommand(log, 'a'));
    scope.undo();
    expect(log, isEmpty);
    expect(scope.canUndo, isFalse);
    expect(scope.canRedo, isTrue);
    expect(scope.lastEvent, UndoEvent.reverted);
  });

  test('redo re-applies the last undone command', () {
    scope.run(_AppendCommand(log, 'a'));
    scope.undo();
    scope.redo();
    expect(log, ['a']);
    expect(scope.canRedo, isFalse);
    expect(scope.lastEvent, UndoEvent.applied);
  });

  test('undo/redo replay strictly LIFO', () {
    scope
      ..run(_AppendCommand(log, 'a'))
      ..run(_AppendCommand(log, 'b'))
      ..run(_AppendCommand(log, 'c'));
    expect(log, ['a', 'b', 'c']);
    scope
      ..undo()
      ..undo();
    expect(log, ['a']);
    scope.redo();
    expect(log, ['a', 'b']);
  });

  test('a fresh run forks the timeline — the redo stack is dropped', () {
    scope
      ..run(_AppendCommand(log, 'a'))
      ..run(_AppendCommand(log, 'b'));
    scope.undo(); // b is now redoable
    expect(scope.canRedo, isTrue);
    scope.run(_AppendCommand(log, 'c'));
    expect(scope.canRedo, isFalse);
    expect(log, ['a', 'c']);
  });

  test('undo on an empty stack is a silent no-op', () {
    scope.undo();
    expect(notifications, 0);
    expect(scope.lastEvent, isNull);
  });

  test('redo on an empty stack is a silent no-op', () {
    scope.redo();
    expect(notifications, 0);
  });

  test('clear drops both stacks and resets the last-event record', () {
    scope
      ..run(_AppendCommand(log, 'a'))
      ..undo();
    notifications = 0;
    scope.clear();
    expect(scope.canUndo, isFalse);
    expect(scope.canRedo, isFalse);
    expect(scope.lastCommand, isNull);
    expect(scope.lastEvent, isNull);
    expect(notifications, 1);
  });
}
