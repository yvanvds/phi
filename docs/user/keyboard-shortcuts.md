# Keyboard shortcuts

Every shortcut and pointer gesture in Phi, grouped by where it works. The
notation is explained in the [guide's conventions](README.md#conventions).

**In the app:** press `Ctrl+/` (or `Ctrl` with the numpad `/`) for the
keyboard shortcuts overlay. It lists the same tables as this page, with the
focused surface first, and you can type to filter it. It is also in the
project menu (`Keyboard Shortcuts`) and in the command palette.

The Scene, State, Racks and Mix surfaces have no keys of their own yet. Their
gestures are on the [Surfaces](surfaces.md) page.

<!-- The tables below are checked against the code by
     test/shell/shortcuts/keyboard_shortcuts_doc_drift_test.dart, which reads
     the same ShortcutCatalog as the in-app overlay. When a shortcut changes,
     change the surface's *_shortcut_hints.dart table (or the command registry)
     first, then paste the table the failing test prints here. -->

## Global

These work everywhere in the window. They are the shell commands that have a
shortcut, so they also appear, with their shortcuts, in the command palette
(`Ctrl+Shift+P`). `Undo` and `Redo` act on the surface you last worked in.

Commands with **no** shortcut, reached through the command palette or a
menu: `Play`, `Stop`, `Toggle Projection`, `Copy Diagnostics`, `New Project`,
`Open Project…`, `Duplicate Project…`, `Rename Project…`, `Settings…`,
`Open Patcher Tutorial…` and `Export Patch as Tutorial…`. The last one is a
developer tool for adding tutorials to Phi.

| Keys | Action |
|---|---|
| `Ctrl+1` | Go to Scene |
| `Ctrl+2` | Go to Patcher |
| `Ctrl+3` | Go to Code |
| `Ctrl+4` | Go to State |
| `Ctrl+5` | Go to MIDI |
| `Ctrl+6` | Go to Racks |
| `Ctrl+7` | Go to Mix |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z`, `Ctrl+Y` | Redo |
| `Ctrl+Tab` | Next Tab |
| `Ctrl+Shift+Tab` | Previous Tab |
| `Ctrl+Shift+P`, `F1` | Command Palette… |
| `Ctrl+/`, `Ctrl+Num /` | Keyboard Shortcuts |
| `F12` | Panic |
| `Ctrl+J` | Toggle Log |
| `Ctrl+S` | Save Project |

## Patcher

With the patcher canvas focused (click on it first). In run mode, only the
navigation keys and `Ctrl+E` answer. See [The patcher](patcher.md).

| Keys | Action | When |
|---|---|---|
| `N`, `Double-click empty canvas` | Insert an object (opens the object box) | edit mode only |
| `Ctrl+E` | Toggle edit ↔ run mode | unavailable while a tutorial is open |
| `Double-click an object` | Retype it / edit its arguments in place | edit mode only |
| `Drag from the palette` | Create an object at the drop point | edit mode only |
| `Delete`, `Backspace` | Delete the selection | edit mode only |
| `Ctrl+D` | Duplicate the selection | edit mode only |
| `Ctrl+C`, `Ctrl+V` | Copy / paste the selection | edit mode only |
| `Ctrl+Z`, `Ctrl+Shift+Z`, `Ctrl+Y` | Undo / redo | edit mode only |
| `Arrows`, `Shift+Arrows` | Nudge the selection one grid cell / one major cell | edit mode only |
| `Esc` | Clear the selection | edit mode only |
| `Shift+click`, `Drag on empty canvas` | Extend the selection / marquee select | edit mode only |
| `Space+drag`, `Middle-drag` | Pan |  |
| `Wheel` | Zoom about the pointer |  |
| `Ctrl+0` | Frame the whole patch |  |
| `Right-click an object` | Object context menu |  |
| `Up`, `Down` | Move through the completions | in the object box |
| `Tab` | Accept the highlighted completion | in the object box |
| `Enter` | Create the object | in the object box |
| `Shift+Enter` | Line break in a note | in the object box |
| `Esc` | Dismiss the box | in the object box |
| `Esc` | Revert the number being typed | in a number box |

## Code

See [Surfaces › Code](surfaces.md#code-ctrl3).

| Keys | Action | When |
|---|---|---|
| `Ctrl+Enter` | Evaluate the block under the cursor | editor focused |

## MIDI

With the piano roll focused. See [Surfaces › MIDI](surfaces.md#midi-ctrl5).

| Keys | Action | When |
|---|---|---|
| `Up`, `Down` | Move the caret one pitch | piano roll focused |
| `Left`, `Right` | Move the caret one snap step | piano roll focused |
| `Enter` | Drop a note at the caret | piano roll focused |
| `Delete`, `Backspace` | Delete the selected notes | piano roll focused |
| `Esc` | Clear the caret, then the selection | piano roll focused |
| `Ctrl+=`, `Ctrl+-` | Zoom in / out horizontally | piano roll focused |
| `Ctrl+wheel` | Zoom horizontally |  |
| `Ctrl+Shift+wheel` | Zoom vertically |  |
| `Middle-drag` | Pan the zoomed roll |  |

## Lists & dialogs

In the command palette, in this overlay's filter list, and in the drop-down
selects used throughout Phi (for example in Settings).

| Keys | Action | When |
|---|---|---|
| `Up`, `Down` | Move the highlight |  |
| `Enter`, `Space` | Run / pick the highlighted entry | Space in a select only |
| `Tab` | Move to the next control |  |
| `Esc` | Close without picking |  |
