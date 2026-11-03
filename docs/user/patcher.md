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
gets an empty one to start with. It stays empty and silent until you add
objects and press `START`.

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

A **message box** shows the message it holds now, which is what a click sends.
A list or a word message arriving on its inlet replaces that message without
sending it, and the box shows the new message. The replacement is not saved:
the patch keeps the text you typed, so the box shows that text again when the
patch is reopened or when you edit its text. In this version of Phi a message
box typed with several words keeps only the first word, and shows only that
word. A newer engine lifts that limit.

**Right-click** an object for its context menu: *duplicate* and *delete*,
*encapsulate*, *open subpatch*, *make abstraction* and *de-encapsulate* on a
subpatch, and *open definition*, *open instance* and *detach* on an instance of
an abstraction (see below).

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

## Subpatches

A **subpatch** is a box that holds a patch of its own, like Max's `p`. Type
`patcher` into the object box, optionally followed by a name: `patcher gain`.
The name is shown on the box and in the window title.

**Open a subpatch** in its own window:

- in run mode, double-click the box;
- in edit mode (where a double-click edits the box's text), right-click it and
  pick *open subpatch*, or select it and press `OPEN SUBPATCH` in the
  reference panel.

Opening a subpatch that is already open brings its window to the front. The
window shows the objects inside the box on a full canvas, with the same
gestures as the main one: insert, connect, move, delete, copy and paste, in
the same `EDIT` / `RUN` mode as the main canvas (the window's bar shows it and
toggles it). A subpatch can hold subpatches of its own; the window title is
the path from the top, for example `fx › gain`.

**Inlets and outlets.** A subpatch has no pins of its own. Its inlets are the
`.inlet` (messages) and `~inlet` (audio) objects inside it, and its outlets
the `.outlet` and `~outlet` objects. Each takes one argument, the pin number,
and messages and audio share one numbering: `~inlet 0` and `.inlet 1` give the
box two inlets, the first for audio. Add, remove or renumber them and the box
changes with them. Inside the subpatch an inlet object shows only its outlet
(what comes in), and an outlet object only its inlet. A pin number that no
object claims is drawn but cannot be connected. A message sent into a
`~inlet` is dropped, so audio and messages need their own inlets.

Cables from the parent connect to the box like to any object. They belong to
the inlet or outlet object behind the pin: renumber that object and the cable
moves with it, delete it and the cable goes too.

**Editing.** Everything you do in a subpatch window is on the patch's one
undo history: `Ctrl+Z` in either window undoes the last edit, wherever it was
made. Deleting, duplicating, copying or pasting a subpatch box takes
everything inside it along. A subpatch with objects inside cannot be retyped
into another object (a banner says so). The contents are saved with the
patch.

**Encapsulate.** Select some objects and press `Ctrl+Shift+E` (or pick
*encapsulate* from the context menu) to move them into a new, unnamed
`patcher` box in their place. Cables between the selected objects stay as they
are. Each cable that ran between a selected object and one outside the
selection now goes through a new pin of the box: a `~inlet` or `~outlet` for
audio, a `.inlet` or `.outlet` for messages. Cables leaving the same outlet
share one pin. Pins are numbered left to right by where the outside end of
their cables sits. Inside, the objects move to the top left of the window,
with the inlets in a row above them and the outlets below. A selection that
holds an inlet or outlet object cannot be encapsulated (a banner says so),
because that object is a pin of the window it is in.

**De-encapsulate** is the reverse. Select a subpatch box and press
`Ctrl+Shift+D` (or pick *de-encapsulate*) to put the objects inside it back
in the window, where the box was. The box and its inlet and outlet objects
go, and every cable that ran through one of its pins now connects straight
from where it came from to where it went. Both are one step on the undo
history: `Ctrl+Z` puts everything back as it was.

The `patcher` tutorial (see [Tutorials](#tutorials)) is a gain subpatch to
play with and open.

A subpatch window closes when its box is deleted, when you switch to another
patch or open a tutorial, and when Phi closes. The reference panel shows a
selected subpatch's name and how many inlets and outlets it has.

## Abstractions

An **abstraction** is a patch you use inside other patches, as many times as you
like. Each use is an **instance**: a subpatch box that holds a copy of the patch
and changes when the patch changes. Any patch can be used this way. Its `.inlet`,
`~inlet`, `.outlet` and `~outlet` objects become the pins of every instance.

**Make an instance** in any of three ways:

- type the patch's address into the object box: `patch.gain`, or
  `patcher patch.gain`. The completion list offers it;
- drag it from the *subpatchers* section of the palette;
- right-click an ordinary subpatch and pick *make abstraction* (or press
  `MAKE ABSTRACTION` in the reference panel). This makes a new patch named after
  the box, holding a copy of what it holds, and the box becomes its first
  instance. Its objects and cables stay as they were. `Ctrl+Z` makes the box
  ordinary again and leaves the new patch in the strip.

The box's name is what makes it an instance: `patcher patch.gain` follows
`patch.gain`. Retype the name to follow another patch.

**Edit the patch, not the box.** Right-click an instance and pick *open
definition* (or press `OPEN DEFINITION` in the reference panel). The patch opens
in its own window, titled with its address, with its own undo history. As soon as
you make an edit, every instance in every patch of the project follows, and so
does anything nested in them. `Ctrl+Z` in that window undoes the edit everywhere.
Objects that did not change keep their sound and their values: changing one
argument does not restart the others.

Cables from the parent stay connected through an edit. A cable moves to a new
inlet or outlet object when that object takes the same pin number and can carry
the same signal. If not, the cable goes and a banner on the parent's canvas says
how many went.

**Play one instance.** Each instance has its own objects, so a slider inside one
is not the slider inside another. In run mode, double-click an instance to open
its own window (or pick *open instance*). That window plays the instance and
stays in run mode, because its contents come from the patch. The patch's own
window plays the patch's objects, which are not the ones you hear unless that
patch is placed on a bus itself.

**Detach.** Right-click an instance and pick *detach* (or press `DETACH`) to keep
what the box holds and stop following. It becomes an ordinary subpatch named after
the patch. `Ctrl+Z` makes it an instance again, and it catches up with any change
it missed.

**A patch cannot contain itself.** The object box and the palette do not offer a
patch that would, directly or through another patch. If you type one anyway, the
box stays as it is and a banner says why.

**Renaming and deleting.** Renaming or moving a patch updates every instance.
Before deleting a patch that is in use, Phi lists the patches using it. Afterwards
their instances keep what they hold and keep sounding, but they can only be played,
and the reference panel marks the definition *not followed*. Detach one to edit it.
Undo the delete, or make a new patch at that address, and they follow again.

**Limits.** What an object saves beyond its arguments, such as a `.preset`'s slots
or a `.function`'s points, is not copied into a new instance. A `.s` and a `.r` with
the same name reach each other across instances, as they do across subpatches.

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

## List boxes

A list box (`l`) shows the list it holds on one line, about ten characters
wide when you place it. A longer list ends in `…`. To read all of it:

- In edit mode, drag the list box's right edge to make it wider or narrower.
  The width is saved with the patch, and `Ctrl+Z` undoes the resize.
- In run mode, hover over a cut-off list to see the whole list in a tooltip.

## The reference panel

The right-hand panel documents the selected palette entry or the selected
object on the canvas, straight from the engine: its description, what each
inlet accepts, what each outlet sends, and its arguments with their defaults
and ranges. For an object on the canvas it also shows the current value of
each argument (`= 250`). When the object type has a tutorial, the panel shows
an `OPEN TUTORIAL` button.
For a subpatch it adds a SUBPATCH section with the name, the inlet and outlet
counts, and an `OPEN SUBPATCH` button.

## Tutorials

Tutorials are example patches that come with Phi, each demonstrating an
object. Find them in the palette's TUTORIALS tab (grouped by category,
searchable), through the reference panel's `OPEN TUTORIAL` button, or with
the command palette's `Open Patcher Tutorial…`. Every object has one. They
cover:

- **GUI basics:** the button (`b`), the toggle (`t`), the slider (`slider`),
  the number boxes (`i` and `f`, which share one tutorial), the message box
  (`m`) and notes (`text`).
- **Single-value controls:** the dial (`dial`), the stepper (`incdec`), the
  lamp (`led`), the labelled button (`textbutton`), the text field
  (`textedit`) and the list box (`l`).
- **Selection and slider controls:** the menu, radio buttons and tabs
  (`umenu`, `radiogroup` and `tab`, which share one tutorial), the range
  slider (`rslider`), the XY pad (`xyslider`) and the slider bank
  (`multislider`).
- **Structured controls:** the grid (`matrixctrl`), the breakpoint editor
  (`function`), the interpolation field (`nodes`), the preset bank
  (`preset`), the keyboard (`kslider`) and the staff (`nslider`).
- **Audio basics:** the oscillators (`~sine`, `~saw`, `~noise`), signal
  ramps (`~line`), the audio input and output (`~adc` and `~dac`, which share
  one tutorial), signal arithmetic (`~+`, `~-`, `~*`, `~/` and `~clip`, which
  share one tutorial), the lowpass and highpass (`~lp` and `~hp`) and the
  bandpass and resonant filter (`~bp` and `~vcf`).
- **Control math:** arithmetic (`+`, `-`, `*`, `/`, `%`, `!-` and `!/`),
  comparisons (`==`, `!=`, `<`, `<=`, `>` and `>=`), logic and bits (`&&`,
  `||`, `&`, `|`, `<<` and `>>`), ranges (`abs`, `round`, `clip`, `scale` and
  `zmap`), math functions (`sin` to `atanh`, `atan2`, `pow` and `sqrt`),
  expressions (`expr` and `vexpr`) and pitch and level conversions (`mtof`,
  `ftom`, `dbtoa` and `atodb`). Each group shares one tutorial.
- **Stateful math:** the counter (`counter`), the accumulator (`accum`),
  change detection (`change` and `togedge`), thresholds and records (`past`,
  `peak`, `trough`, `maximum` and `minimum`), running statistics (`mean`,
  `histo` and `anal`), smoothing and curves (`slide` and `linedrive`), whole
  division, swapping and folding (`div`, `swap` and `pong`) and polar
  coordinates (`cartopol` and `poltocar`). Each group of two or more shares one
  tutorial.
- **Time:** the clock (`metro`), delays (`delay`, and `pipe` for numbers and
  lists), control ramps (`line` and `bline`), rate limiting (`speedlim` and
  `qlim`), measuring time (`timer` and `clocker`) and grouping notes into
  chords (`thresh` and `quickthresh`). Each pair shares one tutorial.
- **Transport, tempo and domain clocks:** starting, stopping and reading a
  named clock (`transport`), counting notes on it (`tempo`), a bang at a beat
  (`timepoint`), a clock for `metro` and `delay` to count beats on
  (`setclock`), asking where a clock is (`when`) and converting between
  milliseconds, beats, ticks and Hz (`translate`). These clocks belong to the
  patch: `START` does not start them. A patch can also follow one of Phi's
  time domains by its address, such as `domain.drum` (see
  [Following a time domain](#following-a-time-domain)); the `transport` and
  `setclock` tutorials show how.
- **Control flow and ordering:** doing things right to left (`trigger` and
  `bangbang`), a loop in one message (`uzi`), conditions (`if`), setting a
  patch up as it opens (`loadbang` and `loadmess`), a one-shot (`onebang`),
  values that belong together (`buddy` and `bondo`), and events and patterns
  (`next` and `match`). Each pair shares one tutorial.
- **Routing:** branching on the first item (`route` and `routepass`), a
  bang for a matching value (`sel`), one way through (`gate` and `switch`), a
  patchbay for messages (`router` and `matrix`), ranges (`split`), spreading
  over outlets (`spray`, `funnel` and `cycle`), and shifting and selecting
  (`bucket` and `decode`). Each group of two or more shares one tutorial.
- **Randomness:** a random number (`random`), a random walk (`drunk`), every
  number once before any repeats (`urn`), weighted chains of states (`prob`)
  and a coin flip (`decide`). `drunk`, `urn`, `prob` and `decide` take a seed
  that replays the same numbers; `random` has none yet.
- **Lists:** building a list from several inlets (`pack` and `pak`),
  splitting one into outlets (`unpack`), one item at a time (`iter`), whole
  lists end to end and fixed-size chunks (`join` and `unjoin`), adding items
  before or after (`prepend` and `append`), the list Swiss-army knife (`zl`),
  and numbering items or swapping one value (`listfunnel` and
  `substitute`). Each pair shares one tutorial. A message box keeps only its
  first word for now, so these tutorials build their lists with `prepend`.
- **Strings and symbols:** formatting numbers and words into a message
  (`sprintf`), matching and replacing with a regular expression (`regexp`),
  a list as one word and back, and parsing typed text (`tosymbol` and
  `fromsymbol`), text and character codes (`atoi` and `itoa`), joining items
  into a name (`combine`), spelling a message out as codes (`spell`) and
  changing case (`tolower` and `toupper`). Each pair shares one tutorial.
- **I/O, messaging and values:** sending without a cord (`s` and `r`, which
  share one tutorial), sending to a name chosen as the patch runs (`forward`),
  one value shared by name (`value`) and writing messages to the log panel
  (`print`). A name belongs to its patch. For now only one `r` of a name hears
  an `s` in the same patch. The `s` and `r` tutorial also shows how to reach
  an `r` from the Code surface: copy it to the project, then
  `patch.tutorials.s_r.send('pitch', 67)`.
- **Subpatches:** a gain subpatch (`patcher`, `.inlet`, `.outlet`, `~inlet`
  and `~outlet`, which share one tutorial). The inlet and outlet objects
  inside the box are its pins, numbered by their argument, with messages and
  audio sharing one numbering. A message sent into a `~inlet` is dropped.
  Double-click the box to open it, read-only, in its own window.
- **Data stores and sequencers:** messages stored at addresses (`coll`), an
  array of ints read as steps or as weights (`table`), a function stored as
  points (`funbuff`), the notes held down (`bag`), a record of what went past
  (`capture`), lines of text (`textfile`), recorded MIDI played back, also on
  a domain clock (`seq`), a timed score that sends to `r` names (`qlist`) and
  a multi-track recorder (`mtr`). The `coll` and `textfile` tutorials write a
  file (`cues.txt`, `lines.txt`) and read it back. A relative file name is
  kept next to `phi.exe` on Windows, and in the folder Phi was started from
  on Linux.
- **Dictionaries:** a named store of keys and values that is saved with the
  patch and shared by name (`dict`), a dictionary built from inlets and taken
  apart again (`dict.pack` and `dict.unpack`), routing on the keys it holds
  and comparing two (`dict.route` and `dict.compare`), walking, splitting and
  trimming one (`dict.iter`, `dict.slice` and `dict.strip`), merging and
  grouping (`dict.join` and `dict.group`), and dictionaries as JSON text and
  in the log panel (`dict.serialize`, `dict.deserialize` and `dict.print`).
  A cord carries only a reference (`dictionary <name>`), never the
  dictionary itself. For now, a dictionary that is loaded with a patch, or
  read from JSON, has its keys in alphabetical order.
- **Arrays:** an ordered list of values that is saved with the patch and
  shared by name, read by position and searched (`array`, `array.at`,
  `array.length`, `array.index`, `array.indexof` and `array.indexmap`), built
  and edited step by step (`array.push`, `array.pop`, `array.shift`,
  `array.unshift`, `array.insert`, `array.remove`, `array.replace` and
  `array.fill`), cut, joined and reshaped (`array.slice`, `array.subarray`,
  `array.split`, `array.wrap`, `array.concat`, `array.flatten`,
  `array.join`, `array.group` and `array.thin`), worked on element by element
  (`array.map`, `array.filter`, `array.reduce`, `array.foreach`,
  `array.every`, `array.some`, `array.expr`, `array.iter`, `array.stream` and
  `array.tuplewise`), reordered and picked from at random (`array.sort`,
  `array.reverse`, `array.rotate`, `array.shuffle`, `array.scramble` and
  `array.random`), summed up (`array.max`, `array.min`, `array.mean`,
  `array.median`, `array.mode` and `array.stddev`), compared as sets
  (`array.union`, `array.sect`, `array.unique`, `array.sub`,
  `array.compare`, `array.change` and `array.routepass`) and converted
  (`array.tolist`, `array.tostring`, `array.tosymbol`, `array.deserialize`
  and `array.regexp`). Each group shares one tutorial. A cord carries only a
  reference (`array <name>`), never the array itself, and where Max sends
  each element out to a callback, Phi's objects take an expression instead.
  For now, place an `array` before the other objects that name it: when one
  of them was placed first, the array opens empty instead of with its saved
  contents.
- **MIDI input:** raw bytes from a MIDI input port, one at a time or framed
  into messages, and taken apart into notes, controllers and the rest
  (`midiin`, `xmidiin` and `midiparse`), notes from a keyboard playing a saw,
  with the release velocity (`notein` and `xnotein`), knobs and faders into
  a filter and a level, also at 14 bits (`ctlin` and `xctlin`), the pitch
  wheel at 7 and 14 bits, and key pressure (`bendin`, `xbendin`,
  `xbendin2`, `touchin` and `polyin`), program changes recalling `preset`
  slots, MIDI clock, start and stop, and SysEx (`pgmin`, `rtin` and
  `sysexin`), parameter messages (`rpnin` and `nrpnin`) and the machine's
  MIDI ports (`midiinfo`). Each group shares one tutorial. The objects
  listen on port 0, the first input `midiinfo` lists. To use another port,
  type its number after the object's name. Without a keyboard they stay
  silent, but you can feed `midiparse` bytes by hand. On Windows a port can
  be open in only one place at a time, so untick it under Settings › MIDI
  for a patch to hear it. For now, at most eight MIDI input objects in all
  open patches can listen to one port, and a ninth stays silent.
- **MIDI output:** notes on a channel, released with a velocity of 0 or with
  a release velocity (`noteon`, `noteoff` and `xnoteout`), a dial as the
  modulation wheel at 7 bits and at 14 (`controlchange` and `xctlout`),
  program changes and pressure (`programchange`, `channelpressure` and
  `polypressure`), the pitch wheel at 7 and 14 bits (`bendout`, `xbendout`
  and `xbendout2`), the pitch-bend range and other parameters (`rpnout` and
  `nrpnout`), byte lists, readable messages and SysEx with a checksum
  (`midiout`, `midiformat` and `sxformat`), and releasing stuck notes
  (`flush` and `midiflush`). Each group shares one tutorial. The builders
  (`noteon` and the rest) take the channel counted from 0, so `noteon 0`
  plays on channel 1, and `midiout` sends what they build to output port 0.
  You hear the notes only when a synthesizer listens on that port. `midiout`
  opens its port on the first message it receives, and that message is
  lost, so each tutorial sends it `allnotesoff` as it opens. To see what is
  sent, each tutorial shows what comes back on input port 0. On Linux, port
  0 is usually `Midi Through` both ways, which sends back whatever it
  receives. Elsewhere, set both ports to a loopback port. A message box
  keeps only its first word for now, so these tutorials build their lists
  with `append` and fill `sxformat`'s placeholders one inlet at a time.
- **MIDI processing:** a metro line of notes that end by themselves
  (`makenote`), counting only note-ons (`stripnote`), giving each note a
  voice for a three-voice saw, with overflow and voice stealing (`poly`), a
  sustain pedal (`sustain`), note statistics such as voices, durations and
  the time between notes (`borax`), number pairs that are read once
  (`offer`), and MPE: a zone, notes with their own pitch bend, pressure and
  slide, and reading them back (`mpeconfig`, `mpeformat` and `mpeparse`,
  which share one tutorial). These objects work on numbers, not on a port,
  and the tutorials play them from keyboards and message boxes on a saw on
  the master bus. The MPE tutorial sends to output port 0 and reads input
  port 0, as the MIDI output tutorials do.

Each tutorial is a small working patch, with numbered notes that walk you
through it. Where Phi's object differs from the Max object of the same name,
the tutorial says so.

A tutorial opens read-only, in run mode. A banner reads
`TUTORIAL — READ-ONLY · <title>` instead of the placement bar, and `Ctrl+E`
does nothing. A tutorial runs while it is open, so its ramps (`line`) and
delays (`delay`, `pipe`) move without you pressing `START`. If it contains an
audio output, you hear it on the master bus. Your own patch is left as it was:
opening a tutorial does not start it. Use `COPY TO PROJECT` to get an editable copy under
`patch.tutorials`. Use `CLOSE` to go back to your own patch. Opening a
project patch also closes it. A tutorial is never saved with the project
unless you copy it.

## Following a time domain

Each of the project's time domains has a clock a patch can follow. Its name is
the domain's address: `domain.drum` for the `drum` domain. Use that name
wherever a clock object takes one: `when domain.drum` reports the domain's
beat and tempo, `timepoint domain.drum 32` bangs at beat 32,
`translate ms beats domain.drum` converts at its tempo, and `metro`, `delay`
and `clocker` count beats on it after `clock domain.drum`.

- **Tempo.** The clock runs at the tempo the domain is played at: its own
  tempo, or the tempo a state applied to it, bent by the tempo fader. When that
  tempo changes, everything on the clock follows.
- **Beats.** The clock counts beats from the moment the project opens, or the
  domain is created. It always runs: `START` and `STOP` do not start, stop or
  reset it, and it has no seek. When Phi restarts audio, for a new device or
  sample rate, the count starts again from 0.
- **Read it, don't drive it.** Phi sets the clock's tempo. Don't send `start`,
  `stop` or a tempo to `domain.drum` from `transport`, `setclock` or `tempo`:
  it would change only the patch objects on that clock, never the domain or its
  clips, and only until the domain's tempo next changes. Give the patch a clock
  of its own to drive instead.
- **Lifetime.** The clock exists for as long as the domain does. Remove the
  domain and objects on its clock stop moving. If a patch named a clock
  `domain.<name>` itself before that domain existed, Phi cannot take that name
  over: the domain's clock appears the next time Phi restarts audio or is
  started again.

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

A patch, like a tutorial, has one audio channel: its `~dac` has a single
inlet and its `~adc` a single outlet.

A patch's edits, placement and the positions of its objects are saved with
the project.
