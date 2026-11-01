# The patcher

The Patcher surface (`Ctrl+2`) is a node-and-cable editor in the spirit of
Max and Pure Data. You build a patch from the audio engine's own objects. A
patch can make sound on a mix bus, or process a bus as an insert effect.

What every object does, with its inlets, outlets and arguments, is documented
in the engine's object reference:
<https://yvanvds.github.io/yse-soundengine/patcher/objects/index.html>. The
same documentation is built into Phi's reference panel (see below).

The surface has these parts:

- **Patches strip** (far left, collapsible): the project's patches.
- **Palette** (left): the OBJECTS and TUTORIALS tabs.
- **Placement bar** (top): where the patch plays, start/stop, snap, and the
  `EDIT` / `RUN` mode.
- **Canvas** (centre).
- **Reference panel** (right).

## Patches

Every patch is a named project item. The patches strip lists them in a tree
(open it with the `show patches` chevron). Use `+` to make a new patch or
group. The `…` menu on a patch duplicates, renames or deletes it. Drag a patch
to reorder it or move it between groups. Renaming refactors, and deleting
warns you when an insert still uses the patch. A project that has no patch
gets one to start with.

One patch is open on the canvas at a time. Click another patch to switch.

## Edit mode and run mode

The canvas is in one of two modes. The placement bar shows which one: `EDIT`,
or `RUN` lit up. Toggle it with `Ctrl+E` or by clicking that indicator.

- **Edit mode** is for building the patch. A press anywhere on an object
  drags it, including faders and buttons. You can marquee-select, connect
  cables, delete, duplicate, copy, paste, nudge and undo.
- **Run mode** is for playing the patch. The controls (sliders, toggles,
  bangs, number boxes, …) answer the mouse, and nothing on the canvas moves
  or gets edited. Undo and redo are off too. You can still pan, zoom and use
  `Ctrl+0` to frame the patch.

Entering run mode clears the selection. The mode is not saved, so a patch
always opens in edit mode.

## Inserting objects

There are three ways to add an object (all in edit mode):

- **Drag from the palette.** The OBJECTS tab lists every engine object,
  grouped by category, with a search field that matches names and
  descriptions. Drop an entry on the canvas to create it there with its
  default arguments.
- **Double-click empty canvas.** An object box opens at that spot.
- **Press `N`.** The object box opens under the mouse pointer, or in the
  middle of the view if the pointer is not over the canvas.

In the **object box**, type the object's name, optionally followed by its
arguments, for example `metro 250` or `sine 440`.

- Completions appear as you type. They match the name with or without its
  `~`/`.` prefix (`sine` finds `~sine`), and they match descriptions.
  `Up`/`Down` move through them and `Tab` accepts one.
- `Enter` creates the object. If the name is already exact, that object is
  created. Otherwise the highlighted completion is.
- A few names belong to both a control and an audio object (`+`, `-`, `*`,
  `/`). Then the box asks you to `pick one`. Move the highlight with an arrow
  and press `Enter` again, or type the full id (`.*` or `~*`).
- Arguments are checked before the object is created. An unknown name or a
  wrong argument keeps the box open with the reason under it, so you can fix
  the typo.
- `Esc`, or a click elsewhere, closes the box without creating anything.

Creating an object is one undo step.

## Objects

An engine object is drawn as a one-line box with its name and arguments, for
example `metro 250`. The `~`/`.` prefix is not drawn. Colour says what kind of
object it is: **audio (DSP) objects are blue**, control objects are grey.
Inlets are the dots on the top edge and outlets the dots on the bottom edge.

**Edit or retype an object** by double-clicking it in edit mode. The box turns
into a text field holding its line, already selected:

- Change the arguments and press `Enter`. The object updates in place.
- Type a different name, for example `saw 300` over `sine 440`, to **retype**
  it. The object is replaced, keeping its position and every cable that still
  fits the new object. If some cables do not fit, a banner says how many were
  dropped (`retyped · 2 cables dropped`). One `Ctrl+Z` brings back the old
  object, its arguments and its cables.

**GUI objects** (bang, toggle, number boxes, message box, sliders, menus,
keyboard, grid, breakpoint editor, presets, …) are drawn as the control
itself, with no box around it. Operate them in run mode, and drag them
anywhere in edit mode. In run mode, dragging a number box up or down changes
its value, and holding `Shift` makes the steps finer. While you type into a number box,
`Esc` puts back the previous value. Controls follow values that arrive over
cables, too.

**Right-click** an object for its context menu: *duplicate* and *delete*.

## Cables

- Drag from an outlet (bottom edge) to an inlet (top edge). You can also drag
  the other way, from an inlet back to an outlet. While you drag, the ports
  that would accept the connection light up. A connection that cannot work
  (for example audio into a control-only inlet) is refused, with a short
  banner saying why.
- Cables are coloured by the kind of data their outlet sends:

  | Colour | Data |
  |---|---|
  | blue | audio signal |
  | lime green | float |
  | orange | integer |
  | magenta | bang |
  | violet | list |
  | grey | any |

- Click a cable to select it, and press `Delete` to remove it.
- To **re-route** a cable, press just beside the port at one of its ends and
  drag. Drop it on another port to reconnect it there, or on empty canvas to
  delete it.

## Selecting, moving and the grid

- Click an object to select it, `Shift+click` to add to the selection, and
  drag on empty canvas to marquee-select. `Esc` clears the selection.
- Drag a selection to move it. The arrow keys nudge it by one grid cell, and
  `Shift` with an arrow by one major cell.
- `Ctrl+D` duplicates the selection. `Ctrl+C` / `Ctrl+V` copy and paste it.
  `Delete` removes it along with its cables.
- The `SNAP` toggle in the placement bar snaps dropped objects to the grid.
- Pan with `Space`+drag or a middle-drag, zoom with the wheel, and press
  `Ctrl+0` to frame the whole patch.

## Notes

A note is a comment on the canvas. It is the engine's `.text` object, so type
`text` followed by your words into the object box. Everything after `text`
is the note's text, not arguments.

- `Shift+Enter` starts a new line. `Enter` still creates the note.
- A line that starts with `# ` is shown as a heading.
- Text wraps. A short note stays small, and a long one wraps at a readable
  width. In edit mode, drag a note's right edge to make it wider or narrower.

Double-click a note to edit its text, the same as any other object.

## The reference panel

The right-hand panel documents the selected palette entry or the selected
object on the canvas, straight from the engine: its description, what each
inlet accepts, what each outlet sends, and its arguments with their defaults
and ranges. For an object on the canvas it also shows the current value of
each argument (`= 250`). When the object type has a tutorial, the panel shows
an `OPEN TUTORIAL` button.

## Tutorials

Tutorials are example patches that come with Phi, each demonstrating an
object. Find them in the palette's TUTORIALS tab (grouped by category,
searchable), through the reference panel's `OPEN TUTORIAL` button, or with
the command palette's `Open Patcher Tutorial…`. So far there are tutorials
for:

- **GUI basics:** the button (`b`), the toggle (`t`), the slider (`slider`),
  the number boxes (`i` and `f`, which share one tutorial), the message box
  (`m`) and notes (`text`).
- **Single-value controls:** the dial (`dial`), the stepper (`incdec`), the
  lamp (`led`), the labelled button (`textbutton`), the text field
  (`textedit`) and the list box (`l`).
- **Time:** `metro`.

Each tutorial is a small working patch, with numbered notes that walk you
through it. Where Phi's object differs from the Max object of the same name,
the tutorial says so.

A tutorial opens read-only, in run mode. A banner reads
`TUTORIAL — READ-ONLY · <title>` instead of the placement bar, and `Ctrl+E`
does nothing. If the tutorial contains an audio output, you hear it on the
master bus. Use `COPY TO PROJECT` to get an editable copy under
`patch.tutorials`. Use `CLOSE` to go back to your own patch. Opening a
project patch also closes it. A tutorial is never saved with the project
unless you copy it.

## Placing a patch

A patch makes no sound until it is placed. There are two ways to place it.

**As a source on a bus.** In the placement bar, pick a mix bus from the
`SRC ›` selector (master, a channel, a group or a return). Then press `START`.
`STOP` silences it, and the `×` beside the bus removes the placement. The
placement is saved with the project. Running is not: a project always opens
with every patch stopped.

**As an insert effect.** On the Mix surface, a strip's INSERTS picker offers
each patch that is not an insert yet as `patcher · <name>`. Picking one puts the patch in that bus's
insert chain, where it processes the bus's audio. From then on it behaves
like any other insert: you can reorder it or move it to another bus, and
deleting the patch warns you that the insert uses it. The insert runs the
same patch you see on the canvas, so an edit is heard at once.

A patch's edits, placement and the positions of its objects are saved with
the project.
