import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';
import '../../surfaces/code/code_shortcut_hints.dart';
import '../../surfaces/midi/piano_roll_shortcut_hints.dart';
import '../../surfaces/patcher/patcher_shortcut_hints.dart';
import '../commands/phi_command.dart';
import '../left_rail/surface_id.dart';
import 'list_shortcut_hints.dart';

/// The one place every shortcut table is gathered (issue #487): the global
/// chords live in the `CommandRegistry`, each surface declares its local ones
/// next to its key handler, and this catalog assembles them into the sections
/// the keyboard shortcuts overlay shows — and the user docs (#486) enumerate.
///
/// To enumerate everything: [global] over the registry's commands (or
/// `buildShellCommands(...)`), then [surfaces] in rail order, then [lists].
abstract final class ShortcutCatalog {
  /// Title of the registry-backed section.
  static const String globalTitle = 'Global';

  /// Each surface's local table, keyed by the surface that owns it. Surfaces
  /// with no local keys yet (Scene, State, Racks, Mix) have no entry.
  static const Map<SurfaceId, ShortcutHintSection> surfaces = {
    SurfaceId.patcher: PatcherShortcutHints.section,
    SurfaceId.code: CodeShortcutHints.section,
    SurfaceId.midi: PianoRollShortcutHints.section,
  };

  /// The pick-list keys shared across the shell (palette, selects).
  static const ShortcutHintSection lists = ListShortcutHints.section;

  /// The global section, read live from [commands]: one hint per command that
  /// advertises a chord, listing its primary chord and every alias. Disabled
  /// commands are kept — the chord is still theirs.
  static ShortcutHintSection global(Iterable<PhiCommand> commands) =>
      ShortcutHintSection(
        title: globalTitle,
        hints: [
          for (final command in commands)
            if (command.shortcut case final shortcut?)
              ShortcutHint(keys: shortcut.labels, action: command.title),
        ],
      );

  /// Every section in overlay order: the [focused] surface's own table first
  /// (when it has one), then [global], the remaining surfaces in rail order,
  /// and [lists] last.
  static List<ShortcutHintSection> sections({
    required Iterable<PhiCommand> commands,
    SurfaceId? focused,
  }) {
    final first = focused == null ? null : surfaces[focused];
    return [
      ?first,
      global(commands),
      for (final id in SurfaceId.values)
        if (id != focused && surfaces[id] != null) surfaces[id]!,
      lists,
    ];
  }
}
