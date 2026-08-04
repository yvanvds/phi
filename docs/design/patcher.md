# Patcher — palette, canvas, and patchers as entities

> Detail doc #6 of [phase2-direction.md](../phase2-direction.md) §4.6.
> Design record, 2026-07-19 — reviewed; decisions in §10. Leads to the
> "patcher" epic on `yvanvds/phi`.
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
  (`args` editable later via params).
- Selecting a palette entry (or a canvas node) shows the **reference
  panel**: description, per-inlet and per-outlet docs with types and
  ranges, creation params — the engine's own documentation, rendered.
  Max-grade discoverability for free.
- DSP objects (`~` prefix) visually distinct from control objects
  (`.` prefix) in the palette, matching cable coloring.

## 6. Canvas interactions

- **Node dragging is body dragging** — click anywhere on a node and
  move it (killing the select-an-outlet-first misfeature); positions
  write through to GUI properties as today. The node stays under the
  pointer at any zoom: the canvas drives the drag from raw pointer
  positions in scene space, so nothing is swallowed by a gesture
  recogniser's slop. A live GUI body (fader, number field, message box)
  owns its own presses — drag those nodes by the header.
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
  offset a grid step).
- **Arrow keys nudge** the selection one grid cell, `Shift+arrow` a
  major one. A held arrow moves on every auto-repeat but journals once,
  on release, so `Ctrl+Z` walks back the whole burst rather than one
  repeat of it — and, like every canvas shortcut, it stays quiet while a
  number box or the inline create box holds the keyboard.
- **Grid snap is optional,** off by default, toggled from the placement
  bar: with it on, a node **drop** (the release of a drag or of a nudge)
  quantises onto the 16px lattice the backdrop paints. The anchor node
  lands on the cell and the rest of the selection shifts by that same
  offset, so a snapped group keeps its arrangement. Only the drop is
  disciplined — the node stays glued to the pointer while it moves.
- **Cursor and hover** teach the hit zones: a move cursor over
  draggable node chrome, a crosshair plus a ring over a port, a pointer
  over a cable, a grab hand where a cable would detach. Resolved from
  the same scene-space hit-tests the presses use, so the cursor is a
  preview of what a press would do rather than a second opinion.
- Undo/redo ride the per-surface command scope, as everywhere.

## 7. Node internals

- **Live GUI bodies** for the interactive control objects — slider,
  toggle, button, number (`.i`/`.f`), message — operable directly on
  the canvas (`sendFloat`/`sendBang` through the gateway, display via
  `guiValue`). The existing slider body generalises.
- **Editable bodies own the keyboard too.** Clicking a number box takes
  focus and selects the value (Max behaviour): Enter commits and pushes,
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
- **Params dialog** (double-click a non-GUI node): one field per
  documented creation parameter (name, doc, default, range from
  `PatcherParam`), applying via `setParams` — the same
  metadata-driven-editor pattern as the MIDI transform editors.

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

- **Subpatcher dive-in editing** — the `patcher` object type exists in
  the engine; v1 does not offer it (see open question 2).
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
   dive-in editing means showing it would be a trap.
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
   message) + metadata-driven params dialog.
7. Entity strip + placement UI: open-patcher selection, new/duplicate/
   rename/delete with impact, source-on-bus picker, start/stop.
8. Insert placement via the racks seam (`fx.` kind `patcher` wrapping
   a `patch.` ref, INSERTS picker integration) — **depends on epic
   #203 (#204, #212)**.
