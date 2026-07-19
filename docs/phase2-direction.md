# Phase 2 Direction — from demos to instrument

> Planning document, 2026-07-17. Sits beside [phi-vision.md](phi-vision.md)
> (the *why*) and [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) (the *what is*)
> — it replaces neither, and it is not the whole of Phase 2's ambition. It
> maps the work that turns Phase 1's connected demos into a usable
> instrument: the features every friendly application is assumed to have,
> plus the deepening of each surface.

## 1. Where Phase 1 left us

Every surface exists and the hard architectural seams are real: the engine
owns the clock and note dispatch, transforms interpret clips in Dart, the
scene spawns live agents, tempo is played rather than set. But Phi is not
yet *usable*: nothing can be saved, nothing has a name, most surfaces are
single-example scaffolds, and the app assumes one window with one visible
surface.

## 2. How this document is used

- **This document** is the stable map: one section per area, each with its
  current state, its goal, and the decisions already settled.
- **Detail docs** live in `docs/design/`, one per area, written
  *just before* that area is worked on — never all up front, so they
  describe intent, not fiction. First one:
  [project-registry.md](design/project-registry.md).
- Each detail doc leads to an **epic issue** on `yvanvds/phi` (pattern:
  issue #105) with child issues, labelled per [CLAUDE.md](../CLAUDE.md).
- Engine gaps discovered while writing a detail doc become issues on
  `yvanvds/yse-soundengine` / `yvanvds/dart-yse` *at that moment* — not
  before, not worked around.

## 3. The organizing decision: a project model

Half of Phase 2's wishlist converges on one missing foundation. Save/load,
autosave, the clip library, racks, mix-channel naming, patcher references,
and live-code addressing all presuppose that Phi has **named, addressable,
serializable entities** — and it has none. So the keystone of Phase 2 is a
**project registry**: one tree of named things, mirrored 1:1 by the
project folder on disk and by the dotted addresses live code uses.

The load-bearing decisions (argued in
[project-registry.md](design/project-registry.md), recorded here for the
map):

- **A project is a folder, not a file.** One small JSON file per entity;
  folders are groups; the file path *is* the registry path *is* the code
  address (`clip.drums.intro_fill` ↔ `clips/drums/intro_fill.json`).
- **Names are identifiers.** Pure-ASCII lowercase `snake_case`, valid in
  Python and safe on NTFS. One validation rule, enforced everywhere.
- **References are names, renames are refactors.** The registry rewrites
  referents on rename/move and warns on delete.
- **Mutations are commands.** Every edit is an undoable command declaring
  the entities it touched — powering per-surface undo
  (**undo follows focus**), dirty-tracking for cheap autosave, and an
  append-only **journal** that makes crash recovery a replay.
- **Voices bind notes to sound.** A voice = {synth, mix bus, color}; clips
  and code address voices, so re-racking a sound touches one file. (The
  scene ↔ voice link is deliberately deferred.)

## 4. Areas

### 4.1 Project model & registry — the foundation

**Now:** nothing persists; entities are singletons wired in the shell.
**Goal:** registry + project folder + commands/undo + journal recovery +
project lifecycle UI (new / open / recent / duplicate / save / autosave).
**Detail doc:** [project-registry.md](design/project-registry.md) —
written and reviewed. Everything else in this map depends on it.

### 4.2 Settings & devices

**Now:** no settings of any kind; the engine picks defaults.
**Goal:** a settings window backed by JSON in `%APPDATA%/phi/` — settings
are per-machine, projects stay portable. First contents: audio output
device, sample rate, buffer size, MIDI input ports, autosave cadence,
recent-projects list, `YSE_DLL_PATH` diagnostics. Nothing project-specific
goes here.

### 4.3 Mix

**Now:** master + N anonymous strips; add-only, no rename/remove/group.
**Goal:** a *small, hand-authored* tree of buses — rename, remove (with
delete-warnings from the registry), grouping via drag. The tree **is** the
signal flow: `yse.Channel.moveTo(parent)` gives real subchannel routing,
and sounds route many-to-one into buses (confirmed engine model). Sends
(`Channel.send` slots) to effect buses. Per-strip: existing fader/mute/solo
+ pre/post metering already in the bridge.
**Settled:** hierarchy = routing; strips stay few (families/stems), the
hundreds of identities live in the scene and share buses.
**Open (for the detail doc):** surround/multichannel output — yse meters
per output; how device speaker layout meets the bus tree.

### 4.4 MIDI — clip library & editor ergonomics

**Now:** exactly one clip; play/stop only; no zoom, snap control, or
clip-length authority.
**Goal:** clips as registry entities with groups (`clip.drums.intro_fill`),
a library panel (select, order, group, duplicate); editor ergonomics —
zoom (h/v), snap divisions, explicit clip length + auto-extend on entry,
loop on/off, pause vs stop, count-in, step-entry basics. Group-level
addresses give group operations (stop all of `clip.drums`) nearly free.
**Settled:** addresses include the group; moving clips between groups is a
rare, deliberate refactor.

### 4.5 Racks & voices

**Now:** the engine has rich synths (SFZ sampler, DX7 FM, virtual-analog +
wavetables, per-note spatial position) with *no UI at all*.
**Goal:** a racks surface to create/configure synth and effect instances
as registry entities (`synth.fm_bells`), and **voices** binding
synth + mix bus + color (`voice.bells`). The piano-roll routing transform,
live code, and MIDI-in all target voices — experimenting with a sound by
playing a MIDI keyboard into a voice is an explicit goal.
**Consequence:** `MidiNote.channel` (int) migrates to a voice reference —
contained in the MIDI domain, planned inside this epic.

### 4.6 Patcher usability

**Now:** a functioning example; node creation is raw, dragging requires
selecting an outlet.
**Goal:** Max/MSP-grade friendliness: an object palette on the left fed by
`PatcherRegistry` (the engine already ships per-type metadata: category,
description, inlet/outlet/param docs — no hard-coded catalogue), with
filter/search and drag-to-canvas; normal node dragging; typed cable
feedback (DSP vs control, from `isDspInput`/`outputDataType`); inline
param editing from `PatcherParam` metadata; patchers as registry entities
addressable from code.

### 4.7 Live coding — the `phi` library & completion

**Now:** the engine's embedded Python exposes bus primitives only
(`send/on/schedule/latch`) — strings everywhere by design; Phi's evaluator
is still `NoOpCodeEvaluator` (issue #9 pends).
**Goal:** a `phi` object layer over the bus: dot-access namespaces
(`voice.bells.note(60)`, `clip.drums.intro_fill.start()`) backed by
`__getattr__` proxies whose methods publish to bus addresses — no strings
in user code. The host mirrors the registry into the interpreter (create /
rename / delete). **Resolve once, bind the object** is the library idiom,
so running scripts survive renames.
**Editor completion is registry-driven, not LSP:** typing `voice.` pops a
list straight from the Dart registry — live, accurate, Phi-flavored
(swatches, lengths). One level deeper completes from a static description
of the proxy API. A real language server is a possible later upgrade.
**Engine dependency:** engine-side routing of `synth/...` bus addresses to
synth objects, and a name table pushed over FFI — yse/dart-yse issues when
this area starts.

### 4.8 State graph

**Now:** author states/transitions, arm, fire — but states configure
nothing beyond guarding MIDI-graph branches.
**Goal (this phase, modest):** make states *do* something — a
`StateSnapshot` that captures/applies a chosen slice of registry state
(which clips play, voice→synth bindings, mix levels), transition actions,
and inspector editing. Morphing transitions stay Phase ≥ 3.

### 4.9 Shell — tabs, splits, windows, palette

**Now:** one window, one surface visible, rail switching.
**Goal:** VS-Code-style **tabs + split views** first (drag a surface to a
half/quadrant), because the clip library, racks, and mix all need "where
does this UI live" answered once. **Multi-window** (very wide external
screen; projected view later) rides Flutter's still-maturing desktop
multi-window support — needs a research spike before promises. Layout
persists per project. A **command palette** (Ctrl+Shift+P) lands here too:
cheap, and it doubles as discoverability + the keyboard-shortcut registry.
The tab/split slice is deliberately pulled *early* in wave 2.

### 4.10 MIDI recording, metronome & panic

> Corrected 2026-07-19: this area is about **recording MIDI-in into the
> piano roll**, not audio performance capture — the earlier
> record-to-disk wording overstated intent. Audio capture/bounce, if it
> ever returns, is its own future design.

**Now:** notes enter the roll by mouse or step entry only; no click, no
count-in, no panic.
**Goal:** record played MIDI into the edited clip's *source* — raw, never
input-quantised (interpretation stays the chain's job), timestamped on
the session's engine clock, overdubbing per loop pass with per-pass undo;
a **metronome/click** session on a chosen time domain (polytemporal like
everything else); **count-in**; and a **panic** action (stop sessions +
all-notes-off + clear spawns) on a permanent shortcut.
**Engine dependency:** none — parsed MIDI-in and the audition path come
from the racks design.

### 4.11 Diagnostics & resilience

**Now:** engine log exists (`Log.messages`); nothing surfaced; a crash
loses everything.
**Goal:** log panel/file with levels; crash-recovery UX (journal replay
with sentinel, from 4.1); status-bar health (engine CPU/drops already
shown — extend with audio-device state); "report what broke" affordance
for a solo dev debugging their own set the morning after.

## 5. Deliberately out of scope for Phase 2

- **Scene editor deepening** — the pick/grab/volume machinery continues on
  its own track; no new scene UI is planned *from this map*.
- **Agent ↔ voice binding** — the design isn't settled; nothing here
  blocks it.
- **Controller integration, VST hosting, cross-platform** — per the vision
  document's deferred list.
- **Audience projection view** — waits for multi-window plumbing (4.9) but
  is its own later design.

## 6. Sequencing

Three waves; within a wave, order by current pain.

| Wave | Areas | Rationale |
|------|-------|-----------|
| 1 — foundations | 4.1 registry/persistence/undo, 4.2 settings | Everything else serializes into, addresses through, or is configured by these. |
| 2 — surfaces | 4.9 tabs/splits (pulled early) · 4.3 mix · 4.4 clip library + roll · 4.5 racks & voices · 4.6 patcher · 4.7 live coding · 4.8 state graph | Each is its own detail doc + epic; live coding (4.7) wants the registry mirror, racks (4.5) before or with it. |
| 3 — performance ergonomics | 4.10 record/metronome/panic, 4.11 diagnostics, 4.9 multi-window + palette polish | Valuable once there is something to record and lay out. |

A wave need not complete before the next starts; the rule is only that a
detail doc is written (and its engine dependencies filed) before its epic
opens.

## 7. Definition of "usable" (Phase 2 exit)

Open Phi → new project → create a synth and a voice → sequence a clip in
the library → route it through the mix tree → tweak it live from code with
completion → save → crash it on purpose → reopen and recover → play the
same set again. When that loop is boring, Phase 2 is done.
