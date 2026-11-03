# Patcher — palette, canvas, and patchers as entities

> Detail doc #6 of [phase2-direction.md](../phase2-direction.md) §4.6.
> Design record, 2026-07-19 — reviewed; decisions in §10. Leads to the
> "patcher" epic on `yvanvds/phi`.
>
> **Revised 2026-08-05** (epic #375, revision issue #376): object boxes
> replace headered nodes, ports move to the top and bottom edges, an
> edit/run mode replaces header-dragging, and the params dialog retires.
> The five review decisions behind that are §12; §5–§7 carry the amended
> text with the superseded rule kept visible beside it, because *why* the
> header was dropped outlives a document that never had one.
>
> **Depends on:** the racks & voices design
> ([racks-and-voices.md](racks-and-voices.md), epic #203) for the
> fx-insert placement role only — everything else in this epic builds on
> shipped code (registry, mix tree). Where this doc touches 4.5
> territory it references the *reviewed design*, not implementation.

## 1. The problem

The Patcher surface is a fixed demo: one global engine patcher mounted
to master, two hardcoded node types (sine, slider), node dragging that
requires selecting an outlet first, no palette, no persistence, no
notion of *which* patcher — it is not an entity, cannot be named,
saved, or addressed. Meanwhile the engine ships a full Max-style object
catalogue *with documentation metadata* that Phi simply never reads.

## 2. What exists to build on (confirmed)

Engine (dart-yse):

- **A self-describing object catalogue.** `PatcherRegistry` enumerates
  every object type with its category (`PCategory`), one-line
  description, per-inlet docs + accepted-message kinds, per-outlet docs
  + data type (`OutType`), and creation-parameter docs with defaults
  and ranges — `metadataJson()` hands the whole reference over in one
  call. The palette and a help panel need **no hardcoded catalogue**.
- **Typed pins.** `isDspInput(inlet)`, `outputDataType(pin)`, and the
  inlet `accepts` bitmask — enough to color cables by signal kind and
  reject invalid wirings at drag time.
- **Full graph API** — `createObject` / `deleteObject` / `connect` /
  `disconnect`, object enumeration, `setParams`, GUI values and
  properties, and control I/O: `passBang/Int/Float/String` into named
  `.r` receivers.
- **Persistence is engine-native:** `dumpJson()` / `parseJson()`
  round-trip the whole graph.
- **Two audio roles already exist:** `Sound.fromPatcher(p, channel:)`
  (a patcher as a sound source on a mix bus) and
  `DspObject.patcherInsert(p)` (a patcher as an insert effect — the
  fx kind the racks design reserved).

Phi (shipped):

- `PatcherGateway` already wraps create/connect/inspect/sendFloat and —
  usefully — **persists node positions into the engine's GUI
  properties**, so `dumpJson` round-trips layout. It is single-instance
  and hardwired to master; this epic generalises it.
- The canvas, cable layer, and ghost-cable rendering exist and carry
  over; the interaction model is what changes.

## 3. Patchers as entities

- `patch.` joins the registry: groups, ordering, rename-refactor,
  delete-impact — the standard affordances.
- **The payload is the engine dump.** `dumpJson` is the graph *and*
  layout source of truth (positions ride in GUI properties — settled
  by the shipped gateway). The payload wraps it with the usual
  kind/version envelope; save = dump, load = parse. No parallel
  Phi-side graph model to keep in sync.
- Edits go through journaled commands at *gesture* granularity (add
  object, connect, move — each a command wrapping the incremental
  gateway call), with the dump refreshed into the payload on save and
  autosave — the dump is the state, the commands are the journal.

## 4. Roles and placement

What a patcher *is* in the sounding world — three roles in v1:

1. **Source on a bus:** the patcher renders as a `Sound` on a chosen
   mix bus (generalising today's hardwired master mount). Good for
   generative/self-running patches. Started/stopped explicitly.
2. **Insert effect:** an `fx.` entity of kind `patcher` wrapping a
   `patch.` reference, placed through the mix INSERTS area — exactly
   the seam the racks design reserved (racks doc §5). *This role waits
   on epic #203 (#204 fx kinds, #212 INSERTS UI).*
3. **Control processor:** named receivers addressed via `pass*` — the
   seam live code will drive (`patch.swirl.send("cutoff", 0.4)` shape,
   detailed in the live-coding doc). No UI in this epic beyond the
   receivers existing in patches.

**Deferred: clip-note dispatch into patchers.** `ClipTransport`
connects to synths and MIDI-outs only; driving a patcher's `.noteon`
objects from clip playback would need a new engine sink. That is a
yse issue to file *when wanted* — not assumed by anything here (the
patcher MIDI objects remain usable via external loopback or future
live-code control).

## 5. Palette and reference panel

- Left palette fed entirely by `PatcherRegistry`: sections by
  `PCategory`, a search box filtering on name + description,
  drag-to-canvas creates the object with its documented defaults
  (`args` editable afterwards on the box itself — §7).
- Selecting a palette entry (or a canvas node) shows the **reference
  panel**: description, per-inlet and per-outlet docs with types and
  ranges, creation params — the engine's own documentation, rendered.
  Max-grade discoverability for free.
- **Colour tells DSP from control — not a glyph.** A DSP object reads
  in the same blue the cables and the overview already carry; a control
  object in the ordinary foreground. The `~` / `.` prefix stays the
  canonical type id you *type*, and the search box and the completion
  list still match on it; it is simply not something you have to read on
  every entry. The palette's leading DSP/control dot goes with it, being
  the same fact said twice (§12.4).
- **An ambiguous bare name is picked, never guessed.** Four pairs share
  one — `.+ ~+`, `.- ~-`, `.* ~*`, `./ ~/` — so an Enter on `*` in the
  inline create box refuses, names both candidates (`pick one · .* or
  ~*`) and leaves the completion list up in their two colours. One more
  keystroke settles it: an arrow moves the highlight, a second Enter
  takes what is highlighted. The prefixed id typed in full is exact and
  never asks, and an unambiguous bare name (`sine`) resolves straight
  through as it always did. The **reference panel keeps the canonical
  id** in its heading — it is where you look the exact name up.

  > *Superseded 2026-08-05 (#376, decision §12.4):* "DSP objects (`~`
  > prefix) visually distinct from control objects (`.` prefix) in the
  > palette, matching cable coloring" — a drawn prefix plus a leading
  > dot. Kept here because the cable-colour *match* survives the change;
  > only the way the palette states it does not.

## 6. Canvas interactions

- **Inlets sit on the top edge, outlets on the bottom,** spread
  horizontally — Max's arrangement, and cables therefore drop out of the
  bottom of one box and arrive at the top of the next. This is not
  cosmetics: ports stacked down a vertical edge set a node's *height*
  from its port count, so a `.*` with two inlets could never be shorter
  than roughly 64px however little it had to say — a one-line object box
  (§7) is impossible while that holds. On the horizontal edges the port
  count sets a node's *minimum width* instead, which a line of text
  happily absorbs. Ports are computed from the live topology the gateway
  reports, so nothing about this migrates: only node *positions* persist,
  and they are untouched (§12.1, epic slice #377).
- **Node dragging is body dragging** — click anywhere on a node and
  move it (killing the select-an-outlet-first misfeature); positions
  write through to GUI properties as today. The node stays under the
  pointer at any zoom: the canvas drives the drag from raw pointer
  positions in scene space, so nothing is swallowed by a gesture
  recogniser's slop.
- **Edit mode and run mode** decide who owns a press on a live GUI body,
  because with the header gone there is no neutral chrome left to drag a
  fader by. In **edit mode** bodies are inert — a fader doesn't move, a
  number box doesn't take focus — and a press anywhere on a node drags
  it, a marquee sweeps across GUI nodes like any others, double-click
  opens the in-place editor, and `Delete`, `Ctrl+D` and the arrow nudges
  all live. In **run mode** bodies are live and own every press; nodes
  neither move nor select nor delete. Panning, zooming and `Ctrl+0` work
  in both, because navigating is not editing. The toggle sits in the
  placement bar with a visible mode indicator, and `Ctrl+E` flips it —
  read from the key's *position* like `Ctrl+0`, so it survives AZERTY.
  The mode is performance state: per open surface, never persisted, and
  a reopened project starts in edit mode (§12.5, epic slice #378).

  > *Superseded 2026-08-05 (#376, decision §12.5):* "A live GUI body
  > (fader, number field, message box) owns its own presses — drag those
  > nodes by the header." Per-node arbitration worked only while every
  > node had a header; a mode is also what a live-performance surface
  > wants on its own terms.
- **Cables:** drag between an outlet and an inlet, from **either end** —
  forwards from the outlet or backwards from the inlet, Max-style. The
  ghost cable colors by the anchored port's type and the compatible
  ports on the opposite side light up (`accepts` mask + `isDspInput`);
  dropping on an incompatible one rejects visibly. Click a cable to
  select, `Delete` removes it. Grab an existing cable **near one of its
  endpoints** and drag to detach and re-route that end — one journaled
  step, whether it lands on another port or on nothing, which deletes
  it. A press that never travels stays the click that selects.
- **Selection:** click node, shift-click extends, marquee over empty
  canvas; `Delete` removes selected nodes with their cables;
  `Ctrl+D` duplicates selection (objects + intra-selection cables,
  offset a grid step); `Ctrl+Shift+E` encapsulates it into a new subpatch,
  routing every cut cable through a new pin, and `Ctrl+Shift+D` unpacks a
  selected subpatch again (issue #552) — one journaled step each.
- **Arrow keys nudge** the selection one grid cell, `Shift+arrow` a
  major one. A held arrow moves on every auto-repeat but journals once,
  on release, so `Ctrl+Z` walks back the whole burst rather than one
  repeat of it — and, like every canvas shortcut, it stays quiet while a
  number box or the inline create box holds the keyboard.
- **`N` inserts an object** — the keyboard way into the inline object
  box a double-click on empty canvas opens, and the key Max uses. The box
  lands under the pointer when it is over the canvas, otherwise in the
  middle of the viewport. Edit mode only; a plain `N` (no Ctrl/Alt/Meta),
  matched on the letter like `Ctrl+Z`, since `N` sits in the same place on
  QWERTY, AZERTY and QWERTZ. A held `N` opens one box, never a second, and
  an `n` typed into a text field is text.
- **Grid snap is optional,** off by default, toggled from the placement
  bar: with it on, a node **drop** (the release of a drag or of a nudge)
  quantises onto the 16px lattice the backdrop paints. The anchor node
  lands on the cell and the rest of the selection shifts by that same
  offset, so a snapped group keeps its arrangement. Only the drop is
  disciplined — the node stays glued to the pointer while it moves.
- **Navigating the view:** pan by middle-drag, or by **holding `Space`**
  and left-dragging — the habit every canvas app shares, and the one
  that needs no third button. While space is down the cursor is a grab
  hand and a press pans wherever it lands; letting go mid-drag ends the
  pan then and there rather than stranding it, and so does losing the
  keyboard. The wheel zooms about the pointer. **`Ctrl+0` frames the
  patch** — fits every node into the viewport, never magnifying past
  1:1, and reduces to the identity view on an empty canvas. Read from
  the key's *position* rather than its glyph, so it survives a shifted
  digit row on AZERTY.
- **Cursor and hover** teach the hit zones: a move cursor over a node a
  press would drag, a crosshair plus a ring over a port, a pointer over
  a cable, a grab hand where a cable would detach. Resolved from the
  same scene-space hit-tests the presses use, so the cursor is a preview
  of what a press would do rather than a second opinion — which means it
  must also tell the truth about the *mode* it is previewing, since in
  run mode a press on the same pixel plays the object instead of moving
  it.
- Undo/redo ride the per-surface command scope, as everywhere.

## 7. Node internals

- **There are no headers, anywhere.** The object *is* the box. A node
  used to be a 22px uppercase title band plus a body that printed
  roughly the same thing again — two rows and ~70px of canvas for one
  line's worth of information, about twice the pixels a Max patch of the
  same graph spends. What replaces it splits by kind: an **object box**
  is a bordered single line of mono text, and a **GUI object** is its own
  control with no frame around it at all (§12.2, epic slices #379/#381).

  > *Superseded 2026-08-05 (#376, decision §12.2):* every node rendered
  > as a header (`osc · sine`, `out · L/R`) over a body. The display
  > title stops being rendered; if nothing renders it once GUI objects
  > lose their headers too, the field goes rather than lingering dead.
- **The object box is one editable line** — `sine 300`, bordered, as
  wide as its text needs, floored by the minimum width its port count
  demands (§6) and capped at a width past which the line ellipsises;
  one text line plus padding tall. **The box is also the editor:**
  double-click it and type, Enter commits through the same journaled
  `setParams` path an editor dialog would have used, so retyping the
  arguments — or the object's very name — happens where you are looking
  instead of behind a modal (§12.3). Selection ring, armed voice border
  and glow carry over unchanged.
- **Retyping the name replaces the object, in place.** `sine 300`
  becoming `saw 300` is not a reconfiguration — the engine has no verb
  that turns one object into another — so the native object is deleted
  and a new one minted. What makes it an *edit* is what is carried
  across: the node keeps its logical id, its position and its selection,
  and **every cable whose endpoint still exists on the new object is
  re-wired** (the port index still in range on the same side, the types
  still accepting each other — the same `accepts` mask / `isDspInput`
  question a drag asks). The rest are dropped, and **the canvas says how
  many**, through the same transient banner a refused wiring uses: a
  connection that quietly vanished is discovered an hour later, on a
  patch that has gone silent for no visible reason. An unknown name or an
  argument the new type refuses changes nothing at all — it is refused in
  the box, as ever. All of it is **one journaled step**: one `Ctrl+Z`
  restores the old object, its arguments *and* every cable that was
  dropped.
- **Live GUI bodies** for the interactive control objects — slider,
  toggle, button, number (`.i`/`.f`), message — operable directly on
  the canvas in run mode (`sendFloat`/`sendBang` through the gateway,
  display via `guiValue`). The existing slider body generalises. A bang
  is a button, a toggle is a checkbox, a slider is a fader: nothing says
  so in a caption, because the control already does.
- **Editable bodies own the keyboard too** — in run mode, where bodies
  own their presses at all (§6). Clicking a number box takes focus and
  selects the value (Max behaviour): Enter commits and pushes,
  moving focus away commits, Escape reverts to the live `guiValue`. The
  canvas never grabs focus back from such a press and never claims a key
  while one of them holds focus — so Backspace edits text there instead
  of deleting the selection, while `Delete` on a focused canvas still
  removes selected nodes.
- **A number box also scrubs.** Dragging the readout vertically carries
  its value with the pointer (held Shift scrubs finer) — the fast way to
  find a number, where typing stays the exact one. The two share the
  readout because the scrub reads raw pointers: a press that never
  travels is left to the field and takes the caret as ever.
- **Bodies follow the engine, not just their own pushes.** A value
  arriving over a *cable* moves the native object and tells Dart
  nothing, so a body that only re-read after its own push went stale the
  moment the graph did anything by itself. While the patcher is the
  visible tab, a 30 Hz poll re-reads `guiValue` for the nodes whose
  registered body displays one (`NodeDescriptor.readsGuiValue`) and wakes
  only the ones whose value changed. The poll is gated three ways —
  offstage surface, no open patch, no live bodies — so an idle patcher
  costs nothing, and a body the user is holding (a thumb mid-drag, a
  focused number field) keeps what the hand is doing. Polling is v1
  because yse reports on demand only; a per-object dirty flag from
  `dart-yse` would swap in behind `refreshGuiValues`.
- **The params dialog is retired.** Arguments are edited on the box
  (above), and the documentation the dialog used to carry alongside its
  fields is already on screen: the **reference panel** (§5) renders each
  creation parameter's doc, default, range and current value for the
  selected node (#356). A modal that shows what a panel is showing
  anyway, in order to edit what the box can edit in place, has nothing
  left to do (§12.3).

  > *Superseded 2026-08-05 (#376, decision §12.3):* "**Params dialog**
  > (double-click a non-GUI node): one field per documented creation
  > parameter (name, doc, default, range from `PatcherParam`), applying
  > via `setParams` — the same metadata-driven-editor pattern as the MIDI
  > transform editors." The `setParams` path and its journaling survive
  > intact; only the dialog around them goes. Double-click now opens the
  > in-place editor.

## 8. Runtime architecture

- `PatcherGateway` generalises to **per-entity instances**: create /
  dispose an engine patcher per open `patch.` entity, the incremental
  ops keyed by instance; `mountAsSound` becomes
  `mountAsSource(instanceId, busAddress)`; full metadata passthrough
  (categories, docs, params) lands on the gateway so the surface stays
  FFI-free. Fake models all of it.
- `PhiEngine` reconciles `patch.` entities the standard way:
  materialise on open/placement, tear down on delete, dirty-track via
  commands, dump-to-payload on save.
- The surface gains an **entity strip** (which patcher is open — the
  same selection pattern as the clip library panel; one open patcher
  at a time in v1).

## 9. Out of scope

- ~~**Subpatcher dive-in editing**~~ — done in issue #481: a subpatch opens
  in its own window (see §10 decision 2), and "encapsulate selection" (and
  its reverse) in issue #552, and reusable abstractions in issue #553 (§13).
- **Clip-note dispatch into patchers** (§4) — future yse issue.
- **Patcher-as-synth-definition** (a voice playing a patch) — follows
  clip-note dispatch; not designed here.
- **Live-code addressing of receivers** — the seam is §4 role 3; the
  DSL lands in the live-coding epic.
- **Audio-rate analysis nodes, custom object authoring** — engine
  features Phi neither has nor needs yet.

## 10. Review decisions (2026-07-19)

1. **Roles v1 as designed** — source-on-bus + insert (via #203) +
   control receivers; clip-note dispatch deferred behind a future yse
   issue.
2. **The subpatcher object is hidden from the palette in v1** — no
   dive-in editing means showing it would be a trap. *Revisited in issue
   #481:* a `patcher` box now opens in a native window of its own (Flutter's
   windowing API, #478) over the same `PatcherController`, so it is in the
   palette. Contents are ordinary objects of the same native patcher marked as
   inside the box (`PatcherGateway.setContainer`), stored inline in the one
   dump. The box's pins are its `.inlet` / `~inlet` / `.outlet` / `~outlet`
   objects; a cable the parent wires to a pin is recorded on that boundary
   object, by the engine and by the editor alike, and drawn on the box.
3. **Live GUI bodies ship in v1** — the seam already exists and it is
   the Max feel.

## 11. Proposed epic breakdown

Roughly eight issues, in dependency order:

1. Domain: `patch.` entities (payload = engine dump envelope), codec,
   command layer at gesture granularity, back-reference seam for fx
   placements (pure domain, TDD).
2. Gateway: multi-instance generalisation — per-entity patchers,
   `mountAsSource(bus)`, metadata passthrough (categories, docs,
   params, `metadataJson`), typed-pin queries, `pass*` control API
   (Real/Fake).
3. Engine: entity ↔ instance reconciliation, source placement
   lifecycle (start/stop on a bus), dump-to-payload on save/autosave.
4. Palette + reference panel: `PCategory` sections, search,
   drag-to-create, docs rendering.
5. Canvas: body dragging, marquee/multi-select, delete/duplicate,
   typed cable authoring + cable selection/deletion.
6. Node internals: live GUI bodies (slider/toggle/button/number/
   message) + metadata-driven params dialog — *the dialog since retired,
   §12.3; the boxes since lost their headers, §12.2.*
7. Entity strip + placement UI: open-patcher selection, new/duplicate/
   rename/delete with impact, source-on-bus picker, start/stop.
8. Insert placement via the racks seam (`fx.` kind `patcher` wrapping
   a `patch.` ref, INSERTS picker integration) — **depends on epic
   #203 (#204, #212)**.

## 12. Object boxes — review decisions (2026-08-05)

Epic #375, recorded by #376. The canvas built from §5–§7 is readable but
*heavy*: a bang is a `BANG` header with a button inside it, a slider a
`SLIDER` header with a fader inside it, an engine object a header plus a
dim line printing `~sine 440` underneath. Next to a Max patch of the same
graph it is roughly twice the pixels for the same information — and the
arguments, the thing you actually tune, live behind a modal instead of on
the object. Max's answer, which this epic adopts: **the object *is* the
box.**

1. **Inlets move to the top edge, outlets to the bottom** (#377).
   *Because* it is what makes a one-line box possible at all, not
   because it looks more like Max. Ports stacked down the left edge at
   26px spacing set the node's height from its port count: a `.*` with
   two inlets can never be shorter than ~64px however little it says. On
   the horizontal edges the count sets a *minimum width*, which text
   absorbs. Foundation slice — #379 and #381 both need it. Amends §6.
2. **No headers, anywhere** (#379, #381). *Because* the header says what
   the thing already shows: a fader is visibly a fader, and `~sine 440`
   names itself. An object box is a bordered line of text; a GUI object
   is its own control and nothing else. Amends §7.
3. **The box is the editor; the params dialog retires** (#382, #383).
   *Because* the reference panel already renders every creation
   parameter's doc, default, range and current value for the selected
   node (#356) — the dialog's remaining job was editing, and editing
   belongs where you are looking. Double-click the box and type; Enter
   commits through the same journaled `setParams` the dialog used, so
   undo/redo are unaffected. Retyping the **name** commits too (#383):
   the object is replaced in place, keeping its position, its selection
   and the cables the new type still has room for, and the canvas names
   the ones it could not carry — a dropped connection is the one part of
   a retype the eye on the box does not notice. Amends §7.
4. **Colour instead of glyphs** (#380). *Because* the four arithmetic
   pairs (`.+ .- .* ./` against `~+ ~- ~* ~/`) share a bare name, so
   something must disambiguate them — and colour does it without costing
   a character on every box: DSP objects in the blue the cables and the
   overview already use, control objects in the ordinary foreground. The
   prefix remains the canonical type id you *type*, disambiguated by the
   completion list at the moment it matters. Amends §5.
5. **Edit / run mode** (#378). *Because* dropping headers takes away the
   one piece of neutral chrome a GUI node could be dragged by, and
   per-node arbitration ("bodies own their presses") then leaves a slider
   unmovable and un-marquee-able. A mode resolves it globally — and a
   live-performance surface wants the split regardless: a state where the
   patch is *played* and nothing can be nudged out of place by accident.
   Edit mode: bodies inert, everything drags. Run mode: bodies live,
   nothing moves. Amends §6.

**Done when** (epic-level): a patch of `sine 300 → * 0.4 → dac` reads as
three one-line boxes with the DSP ones in blue and cables dropping from
bottom edge to top edge; a bang, a toggle and a slider sit on the canvas
as a button, a checkbox and a fader with no chrome around them;
double-clicking `* 0.4` and typing `* 0.8` changes what is sounding
without a dialog; flipping to run mode makes the whole patch playable and
immovable — and the whole thing takes visibly less canvas than it does
today.

## 13. Abstractions — decisions (2026-11-03)

Issue #553, the other half of Max's split: #481 gave the `p` (contents stored
inline in the parent), this gives the abstraction (one patch, saved once, used by
name from several parents, every use following when it changes). The issue left
three questions open and nobody was available to answer them, so they were settled
from the code, taking the more capable design where there was a choice. All of
them are here to be reviewed and overturned.

1. **The definition is a `patch.` entity, referenced by address — not a file.**
   *Because* an entity already has everything a file would have to reinvent:
   names, groups, rename-as-refactor, delete-impact, save, the entity strip. It is
   how `fx.` wraps a patch for an insert (§4 role 2), and any patch can be used
   this way with nothing to convert. A file would also add a second place patches
   live, and nothing in Phi needs a patch to exist outside its project.
2. **The reference is the box's name.** `patcher patch.gain` is an instance of
   `patch.gain`; any other name is an ordinary subpatch (`PatchAbstraction`). *Not*
   a hidden GUI property, *because* an object box shows what it is (§7), and because
   it costs nothing elsewhere: the name already rides through duplicate, paste, undo
   and save, retyping it re-points the box, and the editor needs no other state.
   `patcher patch.nothing` before this feature meant a subpatch named that; such a
   box now reads as an instance whose definition is missing, and keeps its contents.
3. **An instance's contents are stored inline in the parent's dump, as a copy.**
   *Because* the engine keeps a subpatch in the parent's flat graph, so a copy is
   what sounds anyway, and storing it means `parseJson` alone gives a working patch:
   no ordering between patches at load, an instance that keeps sounding when its
   definition is gone, and no change to the insert or source roles. The cost is that
   a parent's file repeats its definitions. On load the copies are compared with the
   definitions and corrected, so a definition is the truth and the copy a cache.
4. **Instances are reconciled, not rebuilt** (`PatchInstanceMaterialiser`). The
   issue expected a rebuild. Objects are paired by type, arguments and position,
   surest match first, and only the differences are written. *Because* a rebuild
   resets every delay line, GUI value and saved state in every instance whenever a
   definition's argument changes, and because a kept boundary object keeps the
   parent's cables, and the undo steps that name them, with no re-wiring at all.
   When a boundary object does go, its cables move to whichever object now claims
   that pin if the types still accept them; otherwise they are dropped and the
   parent's canvas says how many. No patcher is disposed or remounted for any of
   this, only objects inside one, so it stays away from the #548 teardown deadlock.
5. **Instances follow as soon as a definition's edit is journaled**
   (`PatchAbstractionSync`, off each editor's undo scope), not on an explicit save
   like Max's. *Because* Phi has no per-patch save, and hearing the change is the
   point of a live surface. The sync compares rather than tracks changes, so it also
   puts right what an undo or paste brought back from an older definition, in
   dependency order so nested abstractions settle in one go. It works on every patch
   in the project, not only the open one, so it binds an editor to any patch involved.
6. **Editing is on the definition; a box can also be detached. Both, not either.**
   *Open definition* opens the patch itself in its own window (a `SubpatchWindows`
   entry with no box, over the definition's own editor and journal), and every
   instance follows. *Detach* renames the box to the definition's name, leaving an
   ordinary subpatch that keeps its contents, as one undoable step. *Make
   abstraction* is the way in from the other side: a box's contents become a new
   patch and the box its first instance, with its objects and cables untouched.
7. **An instance's own window is played, not edited.** Opening an instance rather
   than its definition (a double-click in run mode, *open instance*) shows that
   instance's objects, held in run mode. *Because* a definition's window plays the
   definition's objects, which are not the ones sounding, so a slider inside an
   instance would otherwise be out of reach; and an edit there would be overwritten
   by the next sync. Run mode's double-click therefore goes to the instance, as
   playing is what run mode is for.
8. **A patch cannot reach itself.** The object box and palette do not offer such a
   definition. One typed or pasted in anyway makes no copy: every reference on the
   loop stops following, keeps what it holds, and the canvas says why. Refusing at
   the sync rather than at each gesture covers typing, paste, undo and rename at once.
9. **A missing definition leaves its instances alone.** Deleting one lists its users
   first (the patch's registry references are the definitions it uses, kept current
   by the sync). Afterwards they keep their copy, sounding, held read-only until
   detached, and the panel says the definition is not followed. Undoing the delete,
   or making a patch at that address, picks them up again.

### `#0`: names per instance (issue #561)

An instance is a copy in the parent's flat graph, and a shared name is scoped to the
native patcher, so a `.s` / `.r` pair in a definition used to talk across every instance
in a patch. These were settled the same way, from the code.

10. **The token is `#0`, as in Max, and it reads `#<number>` in a copy.** `.s ping#0` in
    the definition is `.s ping#3` in instance 3. `$0` was the alternative (Pure Data's),
    but `$` already means something to `expr`, `regexp` and sysex in the engine, where
    `#` means nothing: the engine's tokenizer splits on whitespace only, a string
    parameter keeps the token as it is, and the bus matches addresses exactly, with no
    globbing. Unlike Max it keeps the `#` rather than becoming bare digits. *Because* a
    `#` cannot run into a name somebody typed (`voice#0` as `voice1` would be the same
    name as a `voice1` in the parent, and Max only avoids this by starting at a high
    number), and because a window showing `ping#3` says where the name came from.
    The token is meant for names. A numeric argument refuses it already, in the object
    box (`~sine #0`: "must be a number"), so nothing depends on the copy reading as digits.
    It is replaced anywhere in the arguments of any object except a note, whose text is
    prose. `#01` and `#10` are not the token.
11. **The number lives on the box, in its GUI properties** (`PatchGuiProperty.
    instanceNumber`), not in its name. *Because* decision 2 makes the name the
    reference, and it is what a person types: `patcher patch.gain #3` would be text to
    keep out of the way of retyping, rename-following and `referenceIn`. A GUI property
    is saved in the dump and carried by undo, duplicate and paste with no new machinery,
    and it means nothing to the engine. The reference panel shows it, because that is
    what a parent, or the Code surface, needs to reach one instance (`.s ping#3`,
    `patch.song.send('ping#3', 1)`).
12. **Unique per patch, not per project.** *Because* the engine scopes every shared name
    to `patcher.<patch>.<name>`, so two patches cannot collide, and no project-wide
    counter has to be saved or kept honest. `numberInstances` runs on each patch that
    uses an abstraction at the start of the sync's pass over it. A box with no number
    gets the next one; a box that arrived with a number another box already holds
    (a duplicate, a paste, a redo) gets the next one and is respelled in place, and
    the box that had the number first keeps it. A number is past every number in the
    patch and every number given out this session, so one freed by a delete is still
    free when an undo brings the box back. This pass needs no definition, so an instance
    whose patch is gone is told apart from its duplicate too. Nested instances are
    numbered like any other box in the patch.
13. **Numbers do not move, so names do not move.** Nothing renumbers a box that has a
    number. It survives a save and reload because it is in the dump, a reconcile because
    the materialiser does not copy it from the definition, and a detach because the
    contents still spell it. The comparison does not undo the expansion: the materialiser
    only ever turns the *source's* arguments into what the target should hold, from a
    pair of numbers per window (`#0` to the box's number at the top; for a nested
    instance, the number of the definition's box to the number of the copy's box), and
    compares that with what is there. A copy that reads right gets no native write, so
    an edit elsewhere in a definition keeps a `.r` subscribed and every cable where it
    was. The same translation makes *make abstraction* the inverse: a detached box's
    number goes back to `#0` in the new definition.
14. **Outside an instance `#0` is literal.** A definition's own window shows and runs
    `ping#0`, which is already unique to it, since it is its own native patcher, and an
    ordinary subpatch's `#0` is part of a name shared with its parent. An ordinary
    subpatch inside a definition shares the number of the instance around it, as in Max;
    a nested instance has its own. Only a box that is an instance, or that was one,
    has a number. Expanding in a definition's own patcher too (as Pure Data does) would
    mean showing one string and running another, in every editor path, for nothing.

**Known limits.**

- An object's **saved state** (`.preset` slots, a `.function`'s points) does not
  reach a new copy: a copy is made like a duplicate, from type, arguments and
  decoration, and the gateway has no per-object state write (`yvanvds/dart-yse#111`).
- **A shared name can outgrow the engine's limit in a copy.** `.s`, `.r` and the
  others refuse a name over 63 characters and log it, and a copy's number can be
  longer than the `0` it replaces. A name that close to the limit stops working in
  the instances with the longest numbers. The engine says so in the log; Phi does not.
- **`#` and digits are reserved inside an abstraction that gets nested.** A literal
  `ping#5` typed in a definition stays as it is in a top-level instance. In a nested
  instance the copy is translated from the number of the definition's box, so if
  that box happens to be 5, the literal is taken for the token (`#0`, decision 13).
- A rename rewrites the boxes in the live patches at once and in the payloads at the
  next save. A crash in between replays the move but not the rewrite, so those boxes
  read as missing until retyped. An undo step recorded before a rename that restores a
  box brings the old address back in the same way.
