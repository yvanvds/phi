# The workstation

The workstation is the window around the surfaces. Its parts are:

```
┌───────────────────────── top toolbar ──────────────────────────┐
│ rail │            panes (surfaces, in tabs)          │inspector│
├──────┴──────────────── log panel (when open) ──────────────────┤
└───────────────────────── status bar ───────────────────────────┘
```

## The rail

The column of icons on the left has one button per surface, in this order:
Scene, Patcher, Code, State, MIDI, Racks, Mix. `Ctrl+1` to `Ctrl+7` press
them from the keyboard. Hover a button to see its name and shortcut, for
example `Patcher (Ctrl+2)`.

Each surface exists only once. Clicking a surface that is already open
somewhere brings it forward and focuses it, wherever it is docked. Clicking a
closed surface opens it in the active pane. The lit button is the surface
that has focus.

## Top toolbar

From left to right:

- **Project menu**: the project name. Click it for New, Open, Open Recent,
  Save, Duplicate, Rename, Settings and Keyboard Shortcuts. A dot beside it
  means there are unsaved changes. See [Getting started](getting-started.md#projects).
- **Scene name**: click it to rename the scene in place.
- **Transport**: `play` and `stop`.
- **Metronome**: the click toggle, with a popover where you choose the time
  domain to click on (or the session tempo), the beats, the accent, the
  volume and the count-in before a recording.
- **Projection toggle**: switches projection mode on and off. When it is on,
  the `LIVE` dot in the status bar lights, and the Code surface shows its
  projected view: whole-line comments hidden and runs of blank lines collapsed.

## Panes, tabs, splitting and docking

The centre of the window is a tree of **panes**. Each pane holds one or more
surfaces as tabs. A new project starts with one pane showing Mix.

- **Tabs**: the strip along the top of a pane has one tab per surface in it.
  Click a tab to show it. Its `×` closes the surface (the rail opens it again).
  Drag a tab along the strip to reorder it. `Ctrl+Tab` and `Ctrl+Shift+Tab`
  cycle through the tabs of the focused pane.
- **Split**: drag a tab onto the left, right, top or bottom edge of a pane.
  That pane splits in two, and the surface lands in the new half.
- **Join**: drag a tab onto the centre of another pane, or onto its tab
  strip, to add it to that pane's tabs.
- **Resize**: drag the splitter between two panes. A pane cannot be shrunk
  below a minimum size.

Drop zones only light up while a tab is being dragged. Letting go anywhere
else puts the tab back. Surfaces keep their state when they move, so moving a
half-edited clip or patch loses nothing. Scene is the exception: it is rebuilt
whenever it becomes the visible tab.

The arrangement is saved with the project and restored when you open it.

## The inspector

The narrow strip on the right edge is the inspector. Click it to expand it.
The master volume fader is always at the top. Below it are the properties of
whatever is selected. Today that is a state node on the State surface: its
name, address, slices, on-enter actions and transitions.

## The status bar

The strip along the bottom shows, from the left:

- **`LIVE` dot**: lit while projection mode is on.
- **`PANIC`** (`F12`): stops everything at once. It ends any recording (the
  notes captured so far are kept), cancels a count-in, stops every clip, and
  sends all-notes-off to the MIDI output and to every synth voice. You can
  press it as often as you like.
- **Engine readouts**: `CPU` load, `BUF` (buffer size), `LAT` (latency), and
  `DROPS`, the number of times this session the audio device stalled long
  enough to be heard.
- **Audio chip**: `AUDIO` while a device is open, amber `RECONNECTING` while
  Phi tries to get a lost device back, red `NO AUDIO` once it has given up.
  Click it to open Settings › AUDIO.
- **`MIDI`**: flashes on incoming MIDI.
- **Log toggle**: opens the log panel. When errors have been logged while the
  panel was closed, it shows a badge with their count. Clicking it while the
  badge shows opens the panel filtered to errors.

## The log panel

`Ctrl+J`, the log toggle in the status bar, or the `Toggle Log` command opens
a drawer above the status bar. It holds everything Phi has logged this session.

- Newest entries are at the bottom, and the list follows them as they arrive.
  Scroll up to pause that. A "jump to newest" pill appears, which resumes it.
- The filter bar narrows the list by minimum level, by source, and by a text
  search. The filters combine.
- Drag across entries to select and copy them, or use the header's copy
  button to copy everything currently shown.

Warnings and errors that need your attention also appear briefly as a toast.
The command palette's `Copy Diagnostics` command copies a full report
(app and engine versions, engine library path, audio device and its state,
the open project's path, and the end of the log) for a bug
report.

## The command palette

`Ctrl+Shift+P` or `F1` opens the command palette at the top of the window.
Every shell command is in it, including the ones with no shortcut, such as
`Play`, `Stop`, `Toggle Projection`, `Settings…`, `Open Patcher Tutorial…` and
the project commands.

- Type to filter. The match is fuzzy: `gp` finds `Go to Patcher`. Matched
  letters are highlighted.
- With nothing typed, the commands you used most recently come first.
- `Up` and `Down` move the highlight, `Enter` runs the highlighted command,
  `Esc` closes the palette.
- Each row shows the command's shortcut, if it has one.
- Commands that cannot run right now are hidden. For example, `Stop` only
  appears while the transport is playing.

## The keyboard shortcuts overlay

`Ctrl+/` (also `Ctrl` with the numpad `/`), the `Keyboard Shortcuts` command,
or the project menu item opens an overlay that lists every shortcut. The
focused surface's own shortcuts come first, then the global ones, then the
other surfaces, then the keys that work in lists and dialogs. Type to filter
it. The overlay reads the same tables as the
[keyboard shortcuts page](keyboard-shortcuts.md).

## Undo and redo

`Ctrl+Z` undoes and `Ctrl+Shift+Z` or `Ctrl+Y` redoes. Undo follows focus:
each surface keeps its own history, and the shortcut acts on the surface you
last worked in. In the patcher, undo and redo only work in edit mode.
