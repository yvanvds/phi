# Project Model & Registry — named things, one tree, on disk

> Detail doc #1 of [phase2-direction.md](../phase2-direction.md) §4.1.
> Design record, 2026-07-17 — reviewed; open questions resolved in §12.
> Leads to the "project model & registry" epic on `yvanvds/phi`.

## 1. The problem

Phi has no notion of a named, persistent thing. The MIDI clip is a
singleton wired in the shell; mix strips are anonymous; nothing survives a
restart. Meanwhile save/load, autosave, the clip library, racks, voices,
patcher references, delete warnings, and live-code addressing all
presuppose exactly one capability: **entities with stable names that can
be referenced, serialized, and refactored.** This document designs that
capability once, so each surface doesn't invent its own.

## 2. Concepts

- **Entity** — one named object of a **kind** (clip, voice, synth, …).
  Owns its serializable payload. One entity = one file on disk.
- **Group** — a named folder inside a kind's namespace. Groups nest.
  Groups are addressable (enabling group-level operations later:
  `clip.drums.stop_all()`).
- **Registry** — the in-memory tree of all entities and groups, the
  single source of truth while running. A `ChangeNotifier`; surfaces
  watch it.
- **Address** — the dotted path naming an entity or group:
  `kind.group….name`. The same string is the Python attribute chain, the
  registry key, and (mapped to slashes) the file path.

### Entity kinds

| Namespace | Entity | Arrives with |
|-----------|--------|--------------|
| `clip.`   | MIDI clip | registry v1 — migrate the singleton demo clip |
| `mix.`    | mix bus/channel | registry v1 — migrate current strips |
| `voice.`  | voice (synth + bus + color) | racks & voices epic (§10) |
| `synth.`  | synth/effect rack instance | racks & voices epic |
| `patch.`  | patcher | patcher epic |
| `code.`   | code block | live-coding epic |
| `domain.` | time domain | registry v1 — migrate `TimeDomainRegistry` |

The registry core is kind-generic from day one; kinds populate as their
epics land. Migrating an existing singleton into the registry is part of
each epic's cost.

## 3. Names and addresses

```
address := kind '.' segment ('.' segment)*
segment := [a-z_][a-z0-9_]*        (max 64 chars)
```

Validation — one function, shared by every create/rename dialog and by
live code that mints entities:

- **Pure ASCII, lowercase `snake_case`.** Valid Python identifier, safe
  on any filesystem.
- **Not a Python keyword** (`class`, `for`, …) — keywords cannot follow a
  dot in Python source.
- **Not a Windows reserved device name** — `con`, `prn`, `aux`, `nul`,
  `com1`–`com9`, `lpt1`–`lpt9` (a file named `con.json` misbehaves).
- **Unique among siblings, case-insensitively** — NTFS is
  case-insensitive, and we enforce lowercase anyway.
- **A group and an entity may not share a name at the same level** —
  `clip.drums` must be unambiguously one thing.

Groups obey the same rule (they are path segments). Display niceties
(spaces, capitals) are *not* supported — one name, used identically in
files, strips, library panels, and code. The constraint buys coherence.

## 4. References and refactoring

- References between entities are stored **by address** (human-readable
  files: `"output": "mix.perc"`, not a GUID).
- The registry maintains a **back-reference index** (who references
  whom). It powers:
  - **Rename/move = refactor.** Renaming or regrouping an entity rewrites
    every referent in the project. A move between groups *is* a rename.
  - **Delete warnings.** Deleting an entity lists what still points at it.
- **Code blocks are the soft spot:** references inside saved code are
  text. Rename offers a textual refactor over `code.` entity sources
  (pattern `kind.old_name` → `kind.new_name`) with a confirmation diff —
  best-effort by design, like every IDE rename.
- **Running Python is out of reach:** a rename cannot rewrite a string
  captured in a live closure. The `phi` library idiom is therefore
  **resolve once, bind the object** (`pad = voice.pad1` holds the proxy,
  not the name) — bindings survive renames. Enforced by convention and
  documentation, not machinery.

## 5. Persistence — the project folder

A project is a **folder** (portable; "duplicate project" = copy folder),
its name carrying a `.phi` suffix so Open dialogs and recents can spot it
(`project.json` remains the actual marker):

```
my_set.phi/
  project.json            manifest: format version, project name, tempo,
                          scene name, session defaults
  clips/
    drums/
      _group.json         optional: display order, cosmetic color
      intro_fill.json
    lead_line.json
  mix/                    tree mirrors the bus hierarchy
  voices/
  synths/
  patchers/
  code/
  assets/                 samples, SFZ, wavetables, recordings —
                          referenced by relative path only
  .recovery/
    journal.jsonl         command journal since last save (§7)
    recovering            sentinel, present only during recovery
```

- **One file per entity**; folders are groups; **path = address**.
- Every entity file carries `kind`, `version` (per-kind schema version,
  for migration), `name`, payload. Pretty-printed JSON — diffable,
  hand-fixable, git-friendly.
- `_group.json` holds what the filesystem can't: explicit display
  ordering and a cosmetic library color (§10 note). Optional; absent
  means alphabetical, no color.
- The **manifest** owns project-wide state (today: `SessionState`'s tempo
  and scene name). The **recent-projects list lives in app settings**
  (`%APPDATA%/phi/`), never in the project.

**Save** rewrites dirty entities only (dirty set from §6) and truncates
the journal. **Autosave** is the same operation on a timer — default
60 s, cadence in settings — and it keeps running while the transport
plays: editing with audio on is indistinguishable from performing, so
suspending it there would silently disable it. A future explicit
*performance mode* may suspend it. Explicit save also exists —
performers want a known-good point.

## 6. Commands and undo

Every registry mutation goes through a command:

```dart
abstract class ProjectCommand {
  String get label;                     // "rename voice.bells"
  Set<EntityAddress> get entitiesTouched;
  void apply(ProjectRegistry r);
  void revert(ProjectRegistry r);
  Map<String, Object?> toJson();        // journaling (§7)
}
```

- `entitiesTouched` drives **dirty tracking** (autosave writes exactly
  these) and journal bookkeeping.
- **Undo follows focus.** Each surface owns an undo scope; Ctrl+Z/Y route
  to the focused surface's stack. No global stack to yank a five-minute-old
  piano-roll edit out from under a mix tweak mid-performance.
- An undo *applies the inverse command*, which is journaled like any
  other — the journal stays a faithful linear history even though undo is
  scoped.
- **Gesture coalescing:** continuous interactions (fader drags, note
  drags, live param-editor keystrokes) mutate transient state freely and
  emit **one command on gesture end** — undo works in human-sized steps
  and the journal doesn't bloat.
- The existing `ClipEditor` undo stack (`lib/domain/midi/edit/`) is the
  prototype: its commands adopt the shared interface and its stack
  becomes the MIDI surface's undo scope. The design generalizes what
  already works.

## 7. Journal and crash recovery

The journal **is** the recovery mechanism (not a maybe):

- Every applied command appends one JSON line to
  `.recovery/journal.jsonl`, flushed to disk per command. Batching
  flushes would only pay above ~1 command per second, which manual
  editing never sustains — and gesture coalescing (§6) already keeps the
  command rate human-scale. Appends are cheap — no entity rewrites
  between saves.
- **Replay is domain-only.** Journal entries record registry mutations
  and *never engine calls*. Recovery = load last save → apply journal
  entries to the pure-Dart registry (engine untouched) → boot the engine
  once from the final state, exactly as a normal load does. Engine
  crashes — overwhelmingly timing/thread-dependent — are not reproduced
  by replaying Dart object edits.
- **Crash-loop guard.** A `recovering` sentinel exists during recovery.
  Crash with the sentinel present → next launch offers: replay all /
  replay to N−1 (walk back to the poison edit) / skip journal, load last
  clean save. A corrupted monolithic autosave offers nothing; the journal
  degrades gracefully.
- Successful save truncates the journal and removes the sentinel.

## 8. Runtime architecture (Dart)

- `lib/domain/project/` — pure Dart: `EntityAddress` (value type),
  `ProjectEntity`, `ProjectRegistry` (ChangeNotifier), `ProjectCommand` +
  per-kind commands, name validation, back-reference index,
  (de)serialization to JSON maps.
- `ProjectStore` seam — reads/writes the folder (`dart:io` is fine in a
  non-Flutter layer); `RealProjectStore` / in-memory fake for tests, the
  same Real/Fake split as `YseGateway`.
- **The registry is the source of truth; the engine syncs from it.**
  `PhiEngine` consumes registry state (channels, later synths) instead of
  owning parallel lists — a refactor absorbed by the v1 migration of mix
  strips and the clip.
- `RegistryMirror` seam (`lib/engine/bridge/`) — pushes create / rename /
  delete / regroup into the engine's Python namespace. **No-op
  implementation until the live-coding epic**; the seam exists from v1 so
  nothing needs re-plumbing later. (Finding, 2026-07-16: the engine's
  `yse` module is bus-primitives-only today — the object table is new
  work, filed on `yvanvds/yse-soundengine` / `dart-yse` when §4.7 of the
  direction doc starts.)

## 9. Project lifecycle UI

- **Menu:** New / Open (folder picker) / Open Recent / Save / Duplicate
  Project / project rename.
- **Dirty indicator** in the title bar; confirm-on-close when dirty.
- **Recovery dialog** on launch when a journal + sentinel is found (§7).
- Recent list, autosave cadence in settings (direction doc §4.2).

## 10. Voices (spec parked here until the racks epic)

A `voice.` entity binds the three things a note needs:

```json
{ "kind": "voice", "version": 1, "name": "bells",
  "synth": "synth.fm_bells", "output": "mix.perc", "color": "amber" }
```

- Clips (routing transform), live code, and MIDI-in address **voices**,
  never synths — re-racking a sound edits one file, no clip or script
  changes.
- `MidiNote.channel` (int) migrates to a voice reference inside the
  racks & voices epic.
- **Color application points are experimental by intent** (2026-07-16
  review): mix strips first; ghost-note coloring in the piano roll is an
  *option to try*, not a commitment — concern noted about repaint cost vs
  usefulness. The voice's color field itself is settled; where it shows
  up is not.
- The scene ↔ voice link is **explicitly out of scope** — undesigned, and
  nothing here blocks it.

## 11. Out of scope for this document

Clip-library panel UX (MIDI epic), settings window (direction §4.2),
tabs/splits (§4.9), any scene work, and the Python `phi` library's API
(live-coding detail doc) — this document only guarantees the registry
supports them.

## 12. Review decisions (2026-07-17)

1. **v1 kinds: clips, mix, and domains.** `TimeDomainRegistry` migrates
   in v1 (issue 7 of §13) — it is nearly a registry namespace already.
2. **Project folder: `.phi`-suffixed name** (`my_set.phi/`) for
   discoverability; `project.json` remains the actual marker.
3. **Autosave: default 60 s**, cadence in settings later. It keeps
   running while the transport plays — editing with audio on is
   indistinguishable from performing. A future explicit *performance
   mode* may suspend it.
4. **Journal fsync: per command.** Batching only pays above ~1 command
   per second, which manual editing never sustains; gesture coalescing
   (§6) already bounds the rate.
5. **Cosmetic clip color: per group only** (`_group.json`), no per-clip
   override for now.

## 13. Proposed epic breakdown

One epic, roughly eight issues, in dependency order:

1. `EntityAddress` + name validation + registry tree (pure domain, TDD).
2. `ProjectCommand` layer + per-surface undo scopes; fold `ClipEditor`
   commands into the shared interface.
3. Back-reference index + rename/move refactor + delete warnings.
4. `ProjectStore`: folder layout, entity files, manifest, load/save,
   format versions.
5. Journal append + truncate-on-save; recovery replay + sentinel +
   recovery dialog.
6. Project lifecycle UI: menu, recents (settings-backed), dirty
   indicator, duplicate.
7. Migration: mix strips, the demo clip, and `TimeDomainRegistry`
   become registry entities; `PhiEngine` syncs from the registry.
8. `RegistryMirror` seam with no-op implementation + tests.
