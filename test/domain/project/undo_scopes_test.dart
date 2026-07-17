import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/undo_scope.dart';
import 'package:phi/domain/project/undo_scopes.dart';

/// A trivial command that flips a counter, so a scope's stack has something to
/// undo and the router can be observed routing to the right one.
class _BumpCommand implements ProjectCommand {
  _BumpCommand(this.onApply, this.onRevert);

  final void Function() onApply;
  final void Function() onRevert;

  @override
  String get label => 'bump';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() => onApply();

  @override
  void revert() => onRevert();

  @override
  Map<String, Object?> toJson() => const {'type': 'bump'};
}

void main() {
  late UndoScopes router;

  setUp(() => router = UndoScopes());
  tearDown(() => router.dispose());

  test('with nothing focused, undo/redo are no-ops and cannot fire', () {
    final scope = UndoScope(id: 'midi');
    router.register(scope);
    // Registered but not focused.
    expect(router.focused, isNull);
    expect(router.canUndo, isFalse);
    router.undo(); // must not throw
    expect(scope.canUndo, isFalse);
    scope.dispose();
  });

  test('focus points undo/redo at the matching scope', () {
    var value = 0;
    final scope = UndoScope(id: 'midi');
    scope.run(_BumpCommand(() => value++, () => value--));
    expect(value, 1);

    router
      ..register(scope)
      ..focus('midi');
    expect(router.focused, same(scope));
    expect(router.canUndo, isTrue);

    router.undo();
    expect(value, 0);
    router.redo();
    expect(value, 1);

    scope.dispose();
  });

  test('undo follows focus — only the focused scope is touched', () {
    var midi = 0;
    var mix = 0;
    final midiScope = UndoScope(id: 'midi')
      ..run(_BumpCommand(() => midi++, () => midi--));
    final mixScope = UndoScope(id: 'mix')
      ..run(_BumpCommand(() => mix++, () => mix--));
    expect([midi, mix], [1, 1]);

    router
      ..register(midiScope)
      ..register(mixScope)
      ..focus('midi');

    // Ctrl+Z with MIDI focused undoes the MIDI edit, leaving mix untouched.
    router.undo();
    expect([midi, mix], [0, 1]);

    // Switch focus to mix; now Ctrl+Z hits the mix stack instead.
    router.focus('mix');
    expect(router.focused, same(mixScope));
    router.undo();
    expect([midi, mix], [0, 0]);

    midiScope.dispose();
    mixScope.dispose();
  });

  test('focus(null) parks the router so no stack is yanked', () {
    var value = 0;
    final scope = UndoScope(id: 'midi')
      ..run(_BumpCommand(() => value++, () => value--));
    router
      ..register(scope)
      ..focus('midi')
      ..focus(null);
    expect(router.focused, isNull);
    router.undo();
    expect(value, 1); // untouched — nothing focused
    scope.dispose();
  });

  test('focusing an unregistered id leaves focused null', () {
    router.focus('ghost');
    expect(router.focusedId, 'ghost');
    expect(router.focused, isNull);
    expect(router.canUndo, isFalse);
    router.undo(); // must not throw
  });

  test('notifies on focus change and on register, but not on a same focus', () {
    var notifications = 0;
    router.addListener(() => notifications++);
    final scope = UndoScope(id: 'midi');

    router.register(scope); // 1
    router.focus('midi'); // 2
    router.focus('midi'); // no-op, same focus
    expect(notifications, 2);

    scope.dispose();
  });

  test('unregister drops the scope and clears focus if it held it', () {
    final scope = UndoScope(id: 'midi');
    router
      ..register(scope)
      ..focus('midi');
    router.unregister('midi');
    expect(router.scopes, isEmpty);
    expect(router.focused, isNull);
    expect(router.focusedId, isNull);
    scope.dispose();
  });
}
