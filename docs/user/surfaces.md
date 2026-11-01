# Surfaces

A surface is one of Phi's seven views of the project. Each one has a rail
button and a `Ctrl+<n>` shortcut. They are listed here in rail order. Their
keyboard shortcuts are on the [keyboard shortcuts page](keyboard-shortcuts.md).

Most items you create on a surface are named project items: clips, patches,
scripts, states, synths, effects, voices and mix buses. They share the same
basic actions. You can create them, duplicate them, rename them, delete them,
put them in groups, and drag them to reorder or regroup. Each one also has a
dotted address, for example `clip.drums.intro`.

- **Renaming refactors.** Everything that refers to the item by name follows
  the new name.
- **Deleting warns.** If other items still refer to the one you are deleting,
  Phi lists them first.
- Every such edit can be undone, and it is saved with the project.

## Scene (`Ctrl+1`)

The Scene surface is meant to show the spatial field, where played notes
appear as agents in 3D space. **There is no 3D renderer for now (#455).** The
surface shows a "3D view unavailable" notice. A MIDI clip whose
transformation chain has a spawn transform still places agents in the field
while it plays, but you cannot see them.

## Patcher (`Ctrl+2`)

The patcher is a node-and-cable editor for the engine's own objects, in the
spirit of Max and Pure Data. A patch can make sound on a mix bus or process a
bus as an insert effect. It has its own page: [The patcher](patcher.md).

## Code (`Ctrl+3`)

The Code surface is a Python editor for live coding against the engine.

- **Script library** (left): the project's scripts. A new project starts with
  a `scratch` script. Select a script to open it in the editor. Your edits are
  saved into the project as you type.
- **Evaluate**: `Ctrl+Enter` runs the block under the cursor. The block
  flashes when it runs. A Python error appears in a strip under the editor,
  and the flash turns red when the error comes from the block you just ran.
  Evaluation only works in a build that includes Python. Otherwise nothing
  runs. What you evaluate is not saved; only the script text is.
- **`fresh` toggle** (header): off by default, so each evaluation adds to
  what is already running. When it is on, every evaluation first cancels
  everything earlier evaluations started.
- **Completion**: after a `phi` namespace and a dot (`voice.`, `clip.`, …)
  the editor offers the project's actual items. After an item's name and a
  dot, it offers that item's methods. Plain Python lines get no suggestions.
- **Projection mode** (the toolbar toggle) shows the code with whole-line
  comments hidden and blank-line runs collapsed.

## State (`Ctrl+4`)

The State surface is a canvas of states (rounded squares) and transitions
(arrows) for moving a performance between sections.

- Right-click empty canvas and choose *new state* to add one there. Right-click
  a state to *duplicate* or *delete* it.
- Drag a state to move it. Drag one of its corner pins onto another state to
  draw a transition.
- Exactly one state is **live**. It is marked `● LIVE`.
- Click a transition arrow to **arm** it. Its target shows an `▲ ARMED`
  capsule. Click that capsule to **fire** the transition, which makes the
  target live and clears every arm.
- Click a state to select it. The inspector on the right then shows its name
  (edit it to rename), its address, the slices it captures, what happens on
  entering it, and its transitions.

Which state is live and which transitions are armed is performance state. It
is not saved. When a project opens, its first state is live.

## MIDI (`Ctrl+5`)

The MIDI surface is a piano-roll clip editor.

- **Clip library** (left, collapsed by default): the project's clips. Select
  one to edit it, and play or loop clips from the list.
- **Piano roll**: click to add a note, drag a note to move it, drag its edges
  to resize it, and shift-drag to marquee-select. A velocity lane below the
  roll lets you click or drag to paint velocities. The keyboard caret (arrows
  to move, `Enter` to drop a note) is listed on the
  [shortcuts page](keyboard-shortcuts.md#midi).
- **Transformation chain** (right): a sidebar of transforms that turn the
  notes you wrote into the notes that play. Examples are transpose, scale,
  quantise, routing to voices, and loop. The transformed result is drawn dimly
  behind your notes as a "ghost".
- **Recording**: arm recording, then play, to capture incoming MIDI into the
  clip. Arming while the clip is already playing punches in. Stopping or
  disarming ends the take and keeps its notes. The metronome and the count-in
  live in the top toolbar.

## Racks (`Ctrl+6`)

The Racks surface is where you define the instruments and effects that voices
and mix buses use. It has three panes:

- **Definitions** (left): the project's SYNTHS and EFFECTS. Add a synth (sine,
  va, fm, sampler) or an effect from each section's add menu.
- **Editor** (centre): the selected definition's parameters. One slider drag
  is one undo step. FM synths browse the patches of an imported DX7 bank, and
  samplers import an SFZ file or a single sample. Imported files are copied
  into the project.
- **Voices** (right): one card per voice. Each card has its colour, its name,
  an arm toggle (play the voice from your MIDI input), internal or external
  kind, the synth it plays (internal) or the MIDI channel (external), and the
  mix bus it goes to. A one-octave test strip below the cards plays the armed
  voice from the mouse.

## Mix (`Ctrl+7`)

The Mix surface is the mixer: a rack of channel strips, with master pinned on
the right.

- **Strips** have a fader with a peak meter, mute and solo, and the voice
  colour. Click a strip's name to rename it. Its `×` removes the strip. Master
  can be neither renamed nor removed. Master shows one meter per speaker
  output.
- **`+`** adds a channel, a group, or a return bus.
- **Groups**: drag a strip's handle onto a group to put it in the group, onto
  another strip to reorder, or onto the open rack to take it out of the group.
- **Returns** sit in their own section beside master. They have no solo.
- **SENDS** (under each strip): add an aux send to a return. Each send has a
  level, a pre/post-fader toggle and a remove `×`.
- **INSERTS** (under each strip): the strip's insert-effect chain. Place an
  effect from the Racks definitions, reorder it, or move it to another bus. A
  patch can also be placed here as an insert. See
  [The patcher](patcher.md#placing-a-patch).
