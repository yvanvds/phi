# MIDI Clips — the library and the editor

> Detail doc #4 of [phase2-direction.md](../phase2-direction.md) §4.4.
> Design record, 2026-07-19 — reviewed; decisions in §7. Leads to the
> "midi clips" epic on `yvanvds/phi`.

## 1. The problem

The registry epic made clips real entities (`clip.phrase_a` seeds a
fresh project; a `ClipDocument` persists source + chain/graph + mode;
issue #139 adopts a loaded document into the live session). But the MIDI
surface still behaves as if there were exactly one clip in the world:

- **No library.** One clip is adopted at open; creating, duplicating,
  grouping, ordering, or switching clips has no UI and no commands.
- **One live clip, ever.** `EngineMidiController` owns exactly one
  chain + editor + graph + transport. Playing two phrases against each
  other — the polytemporal core of the vision — is structurally
  impossible in the UI even though the engine mints per-clip transports.
- **Editor ergonomics stop at the demo.** No zoom (fixed pixel scale),
  no snap picker (the `gridDivision` seam exists with no UI), no length
  authority (bars are data, not editable), loop is always on, stop is
  the only way to halt, import overwrites the open clip.
- `MidiClip` still carries a free-form display name — the same
  one-name divergence the mix epic removed for strips.

## 2. What exists to build on (confirmed)

- **Per-clip transports are already the engine model.**
  `MidiGateway.createTransport({clockName, tempo})` mints a transport
  bound to a *fresh domain clock* — N playing clips = N transports on N
  clocks, exactly the polytemporal shape. Nothing engine-side assumes a
  single transport.
- **Loop on/off is free:** `setEvents(..., loopBeats: <= 0)` disables
  looping (events fire once).
- **Resume is documented:** `MidiTransport.play()` "starts (or
  resumes)" — pause needs no new engine surface, but the engine's
  actual resume semantics must be verified during implementation (a
  small dart-yse issue only if `ClipTransport` can't resume mid-loop).
- **Snap machinery exists:** `ClipEditor.gridDivision` already drives
  click-to-add, drag, and nudge — it only lacks a picker.
- **Adoption exists:** `adoptDocument(ClipDocument)` (#139) swaps the
  live session's content in place — the seam library selection builds
  on.
- **Clip length is data:** `MidiClip.bars` / `beatsPerBar` /
  `totalBeats` exist; nothing edits them.

## 3. The library

A collapsible **library panel** on the left of the MIDI surface (mirror
of the transform sidebar) showing the `clip.` namespace as a tree:

- **Groups are folders** (`clip.drums.intro_fill`), ordered and
  colored by `_group.json` as the registry already supports. Clips
  order within their group by the same mechanism; drag to reorder,
  drag into/out of a group to regroup (= rename-refactor, as settled).
- **One name.** `MidiClip`'s free-form display name is removed — the
  clip is named by its address leaf, shown in the panel, the editor
  header, and live code identically. Same rule, same no-compat stance
  as the mix epic (registry doc §3, mix doc §10.1).
- **Context menu:** new clip · new group · duplicate · rename · delete.
  Duplicate copies the whole document (source + interpretation) to
  `<name>_copy`. Delete goes through the registry delete-impact dialog
  (future referents: state snapshots, live code).
- **Selection opens the clip in the editor** (its session becomes the
  edited one, §4); the editing surface never goes blank — a fresh
  project opens its seeded clip.
- **Import lands in the library:** dropping / importing a `.mid` creates
  a *new* clip entity in the selected group (name slugged from the
  filename) instead of overwriting the open clip. Export writes the
  selected clip's transformed output, as today.

## 4. Sessions and playback

The structural heart of the epic: `EngineMidiController` generalises
from "the clip" to a set of **clip sessions**.

- A `ClipSession` bundles what the controller holds globally today:
  the clip + its chain/graph controller + `ClipEditor` + transport +
  push-on-change memoisation. Sessions are keyed by entity address and
  created lazily (opening a clip in the editor, or starting its
  playback).
- **Any clip can play, concurrently.** Each playing session owns its
  transport on its own domain clock — two phrases in different time
  domains run against each other; this epic turns that from
  architecture into instrument. Play/loop toggles live on the library
  rows (and the header for the edited clip).
- **Group operations** come nearly free, as the direction doc promised:
  play / stop on a group row acts on every clip beneath it
  (`clip.drums` → stop all drums). Stop-all lives in the panel header.
- **Pause vs stop:** pause halts dispatch (with `allNotesOff` so no
  voice hangs) but keeps the beat origin — resume continues where it
  left; stop rewinds. Per session.
- **The editor edits one session at a time** — the selected clip's.
  Ghost painting, the graph canvas, the variables bar, and the preview
  strip all bind to the edited session, exactly as they bind to the
  single controller today.
- **Scene spawning follows every playing session** whose chain carries
  a spawn transform: `SceneField` keys are namespaced by clip address
  (`clip.drums.kick/3`), so concurrent clips spawn side by side and a
  stopped clip clears only its own agents.
- **What persists:** the loop flag, per clip, in its payload — **on by
  default** for new clips (§7 decision 4). Play state is performance
  state and is never persisted — a loaded project starts silent.

## 5. Editor ergonomics

- **Zoom.** `PianoRollGeometry` parametrises (pixels-per-beat,
  lane-height); Ctrl+wheel zooms horizontally around the pointer,
  Ctrl+Shift+wheel vertically; keyboard `Ctrl+=`/`Ctrl+-`. View state
  is session-local, not persisted.
- **Snap picker.** A header `PhiSelect` feeding
  `ClipEditor.gridDivision`: off · 1/1 · 1/2 · 1/4 · 1/8 · 1/16 ·
  1/32 · 1/8T · 1/16T. All existing gestures (add, drag, resize,
  nudge) follow it automatically.
- **Length authority.** Editable bars ×  beats-per-bar fields in the
  header; the loop window is `totalBeats` (the clip's declared length,
  not the output's extent). **Auto-extend:** entering or dragging a
  note beyond the end grows `bars` to fit (rounded up) — a header
  toggle, default on. Shrinking warns when notes would fall outside.
- **Transport row:** play / pause / stop / loop for the edited clip in
  the header strip (the toolbar transport keeps driving the edited
  clip as today).
- **Step entry (minimal).** With the roll focused, `Enter` drops a
  note at the edit cursor (a beat-position caret the arrow keys move by
  one grid step); the caret advances by the grid after each entry.
  Audible preview while stepping waits for voices (racks epic).

## 6. Out of scope

- **Audition / note preview** (click a note, hear it) — needs voices;
  racks & voices epic.
- **Count-in** — meaningless without a click; waits for the metronome
  (direction §4.10).
- **Recording MIDI-in into a clip** — racks & voices epic (input
  routing) + §4.10 (recording).
- **Per-clip mixer/voice assignment UI** — the routing transform
  remains the mechanism until voices land.
- **Clip launching quantisation** (bar-aligned launch, Ableton-style)
  — a performance feature that belongs with the time-domain UI wave;
  play here is immediate.

## 7. Review decisions (2026-07-19)

1. **Concurrent playback is in scope** — multi-clip sessions as
   designed (§4); it is the instrument step, and the engine already
   supports it.
2. **Auto-extend defaults to on.**
3. **Step entry ships now** — the minimal caret version (§5); audition
   still waits for voices.
4. **Loop defaults to on** for new clips.

## 8. Proposed epic breakdown

Roughly eight issues, in dependency order:

1. Clip domain: drop the display-name field (one-name, no compat),
   payload gains the loop flag, codec + seed updates (pure domain,
   TDD).
2. Library commands: new clip · duplicate · import-as-new-entity
   (SMF → document in the selected group), export-selected (pure
   domain + registry commands, TDD).
3. **Sessions refactor:** `ClipSession` extraction;
   `EngineMidiController` becomes the session manager; the editor,
   ghost, graph canvas, and scene/playhead wiring bind to the edited
   session. No behaviour change yet — the single-clip flow must pass
   its existing tests through the new shape.
4. Concurrent playback: per-session transports, play/loop/pause/stop
   semantics (incl. engine resume verification), group play/stop,
   stop-all, scene-key namespacing.
5. Library panel UI: tree with groups, ordering, drag-to-group,
   context menu, selection-opens-editor, per-row play/loop state,
   delete-impact wiring.
6. Editor ergonomics: zoom (h/v, pointer-anchored) + snap picker.
7. Editor ergonomics: length fields + auto-extend + loop toggle +
   pause/stop transport row.
8. Step entry (decision 3) + import/export flow polish (drop-target =
   selected group, filename slugging).
