# Phi user guide

This is the user documentation for Phi, a workstation for live electronic
music performance. It describes what the app does today. The design and
architecture notes for developers are one folder up, in [docs/](../).

The guide is kept in the repository next to the code. A change that alters
behaviour updates the page that describes it in the same pull request.

## Pages

1. [Getting started](getting-started.md): install and run Phi, set up audio,
   and create, open, save and recover projects.
2. [The workstation](workstation.md): the shell around the surfaces. Covers
   the rail, the top toolbar, the transport, the inspector, the status bar, the
   log panel, the command palette, and docking, splitting and tabs.
3. [Surfaces](surfaces.md): what each of the seven surfaces (Scene, Patcher,
   Code, State, MIDI, Racks, Mix) is for, and its basic gestures.
4. [The patcher](patcher.md): patches, edit and run mode, objects, cables,
   notes, the reference panel, tutorials, and placing a patch on a bus or as an
   insert.
5. [Keyboard shortcuts](keyboard-shortcuts.md): every shortcut and gesture,
   grouped by where it works.

## Conventions

- **Platforms.** Phi runs on Windows and Linux (x64). Shortcuts are written
  with `Ctrl` on both. There is no macOS build, so this guide never uses
  `Cmd`.
- **Shortcut notation.** `Ctrl+Shift+P` means: hold Ctrl and Shift, then
  press P. A comma separates alternatives that do the same thing:
  `Ctrl+Shift+Z`, `Ctrl+Y` both redo. Pointer gestures are spelled out, for
  example `Double-click empty canvas` or `Middle-drag` (drag with the middle
  mouse button held).
- **Letter and digit keys follow your keyboard layout.** `Ctrl+Z` is the key
  labelled Z, wherever your layout puts it. `Ctrl+E` and `Ctrl+0` in the
  patcher also answer to the key in the QWERTY position, so they work on
  AZERTY too.
- **The app tells you its own shortcuts.** Press `Ctrl+/` at any time for the
  keyboard shortcuts overlay. The command palette (`Ctrl+Shift+P`) shows each
  command's shortcut next to its name, and the rail's tooltips show
  `Patcher (Ctrl+2)` and so on.
- **UI labels** are quoted the way the app prints them. Many are drawn in
  capitals (`EDIT`, `RUN`, `PANIC`).
