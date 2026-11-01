import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/shell/commands/phi_command.dart';
import 'package:phi/shell/commands/shell_commands.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/shortcuts/shortcut_catalog.dart';
import 'package:phi/surfaces/patcher/patcher_shortcut_hints.dart';

/// The catalog that gathers every shortcut table (issue #487): registry-backed
/// global chords plus each surface's local table, focused surface first.
void main() {
  late SessionState session;

  setUp(() => session = SessionState());
  tearDown(() => session.dispose());

  List<PhiCommand> commands() => buildShellCommands(
    session: session,
    onSummonSurface: (_) {},
    onUndo: () {},
    onRedo: () {},
    onCycleTabForward: () {},
    onCycleTabBackward: () {},
    onOpenCommandPalette: () {},
    onPanic: () {},
    onOpenKeyboardShortcuts: () {},
  );

  test('the focused surface comes first, then Global, then the rest', () {
    final titles = ShortcutCatalog.sections(
      commands: commands(),
      focused: SurfaceId.midi,
    ).map((s) => s.title).toList();
    expect(titles, ['MIDI', 'Global', 'Patcher', 'Code', 'Lists & dialogs']);
  });

  test('with no focused surface (or one with no table) Global leads', () {
    for (final focused in [null, SurfaceId.mix]) {
      final titles = ShortcutCatalog.sections(
        commands: const [],
        focused: focused,
      ).map((s) => s.title).toList();
      expect(titles, ['Global', 'Patcher', 'Code', 'MIDI', 'Lists & dialogs']);
    }
  });

  test('Global lists live chords with their aliases', () {
    final global = ShortcutCatalog.global(commands());
    final byAction = {for (final h in global.hints) h.action: h.keys};
    expect(byAction['Redo'], ['Ctrl+Shift+Z', 'Ctrl+Y']);
    expect(byAction['Command Palette…'], ['Ctrl+Shift+P', 'F1']);
    expect(byAction['Keyboard Shortcuts'], ['Ctrl+/', 'Ctrl+Num /']);
    expect(byAction['Go to Patcher'], ['Ctrl+2']);
    expect(byAction['Panic'], ['F12']);
    // Commands with no chord are not shortcuts.
    expect(byAction.containsKey('Play'), isFalse);
  });

  test('the patcher table notes Ctrl+E is unavailable in a tutorial', () {
    final ctrlE = PatcherShortcutHints.section.hints.singleWhere(
      (h) => h.keys.contains('Ctrl+E'),
    );
    expect(ctrlE.note, contains('tutorial'));
    expect(
      PatcherShortcutHints.section.hints.any((h) => h.keys.contains('N')),
      isTrue,
    );
  });
}
