# Phi — Project Overview

> Read this at the start of any session before exploring code. Updated after
> structural changes; refresh with the `project-overview-update` skill when
> the diff vs `git log` grows.

## What this is

Phi is a flexible workstation for live electronic music performance — see
[phi-vision.md](phi-vision.md) for the full vision. Personal years-long
project, Windows desktop only.

## Stack at a glance

| Layer        | Tech                                                  |
|--------------|-------------------------------------------------------|
| Audio engine | C++ (`yse-soundengine`)                               |
| FFI bridge   | `dart-yse` — Dart wrapper, package name `yse`         |
| UI shell     | Flutter ≥ 3.38, Windows desktop                       |
| Design       | Dart tokens derived from `design system/colors_and_type.css` |
| 3D viewport  | macbear_3d (ANGLE / OpenGL ES 3), pub.dev 0.9.0       |
| Scripting    | Python with DSL (Phase ≥ 2 — not yet)                 |

`dart-yse` lives at `d:\dart-yse` as a sibling on disk and is consumed via
a path dependency. CI clones both repos as siblings.

## Layered folder structure under `lib/`

One-way dependency flow — top depends on bottom, never the reverse.

```
main + app          (orchestration)
├── shell           (workstation chrome)
├── surfaces        (Scene · Patcher · Code · State · MIDI · Mix)
├── engine          (PhiEngine façade + bridge over package:yse)
├── design          (tokens + reusable widgets — no domain knowledge)
├── domain          (pure-Dart models — session/ wired; more arrives later)
├── platform        (windows-specific bits — empty for now)
└── core            (cross-cutting helpers — empty for now)
```

## Current phase

**Phase 1 — Audio hello-world + workstation chrome.** Implemented:
- Design tokens (colors, type, spacing, motion, radii) in `lib/design/tokens/`
- Theme in `lib/design/theme.dart`
- Widget library: `PrimaryButton`, `PeakMeter`, `Capsule`, `PhiToggle`,
  `InlineEditableText`, `TransportButton`, `RailButton`, `StatusChip`,
  `PhiFader`, `ChannelStrip`
- `PhiEngine` façade over a `YseGateway` interface (`RealYseGateway` for
  production, `FakeYseGateway` for tests). Owns the master + N user
  `MixerChannel` instances and exposes add/remove/volume/mute/solo;
  mute/solo are collapsed to an effective gateway volume since YSE has no
  native notion of them.
- `SessionState` in `lib/domain/session/` — pure-Dart cross-cutting state
  (transport intent, projection, scene name)
- Workstation chrome: top toolbar (wordmark, inline-editable scene name,
  play/stop transport, time-domain placeholder, projection toggle), left
  rail (6 buttons, only Mix enabled), bottom status (LIVE dot, CPU + drops),
  right inspector (tap to expand 28→320px, hosts a master-volume fader)
- Mix surface: horizontal rack of `ChannelStrip` widgets (master pinned
  right, user strips left). Header has a `+` to add channels and the
  `System.audioTest` toggle. Each strip carries voice-swatch + name + fader
  with overlaid peak meter + mute/solo buttons.
- Scene surface stub: renderer-agnostic `SceneRenderer` bridge in
  `lib/engine/bridge/`, backed in production by `MacbearSceneRenderer`
  (`macbear_3d` on ANGLE). Renders one placeholder agent as a
  voice-coloured sphere; orbit/pan/zoom via macbear's built-in controller.
- Code surface scaffold: `re_editor`-backed Python editor with custom
  Phi-flavoured highlight theme, projected view (full-line comments
  stripped, blank-line runs collapsed) driven by
  `SessionState.projection`, and Ctrl+Enter dispatching the block under
  the cursor to a `CodeEvaluator` abstraction. The shell wires in
  `NoOpCodeEvaluator` by default — real Python execution
  (embedded-C++ vs. subprocess vs. Dart-FFI) is the next layer's call.
- MIDI surface — editable piano roll plus a 250px transformation-chain
  sidebar of eight chips. Domain in `lib/domain/midi/`: pure-Dart
  `MidiNote` / `MidiClip` (now **mutable**) / `MidiTransform` +
  `MidiTransformChain` (ChangeNotifier). Two transforms work end-to-end —
  `TransposeTransform` and `ScaleConformanceTransform` (snaps to a diatonic
  mode, tie-break upward); the other six chips are `StubTransform`s.
  Editing (issue #28) is a command layer: `ClipEditor` (ChangeNotifier)
  owns the clip, the selection, and an undo/redo stack of `ClipEditCommand`s
  (`lib/domain/midi/edit/` — add / delete / in-place edit). Gestures author
  the **source** clip while the chain's transformed output paints dim behind
  as a "ghost"; `PianoRollGeometry` is the shared pixel↔(pitch,beat) mapping
  so the painter and hit-test never drift. `PianoRollEditor` handles
  click-to-add, drag body/edges (move · resize · move-start), shift-drag
  marquee, arrow-key nudge, Delete, and Ctrl+Z/Y; a `VelocityLane` below the
  roll (shared time axis) does click/drag-to-paint velocity. Playback is
  wired (issue #29): `EngineMidiController` (`lib/engine/state/`) owns the
  chain + editor and drives a looping playhead off a periodic timer,
  reading the chain's transformed `output` **live** each tick (so edits and
  chip toggles are heard immediately, not on the next play) and
  forwarding `noteOn`/`noteOff` through a `MidiGateway` (Real over
  `package:yse`'s `MidiOut`, Fake recording calls in tests — the same
  split as `YseGateway`). `PhiEngine.midi` exposes it; the top-toolbar
  transport drives `play`/`stop` at `SessionState.tempo`, the piano-roll
  painter animates a non-zero playhead, and stop sends `allNotesOff`. The
  shell sources the chain/editor from `engine.midi` when present (falling
  back to its own pair when no MIDI gateway is wired). Still tracked
  separately: SMF file import/export and the remaining transforms.
- State surface scaffold: pan/zoom canvas (reuses the patcher's 16px
  dot grid backdrop) of rounded-square `PerformanceState` nodes with
  four voice-coloured corner pins, plus directed `StateTransition`
  arrows drawn as cubic Béziers between the closest source/target
  edges with arrowheads. Domain in `lib/domain/state_machine/`:
  pure-Dart `PerformanceState` / `StateTransition` / `StateGraph` /
  `StateSnapshot` (ChangeNotifier where mutable, immutable value
  type for `StateSnapshot`). `StateMachineController` (pure Dart,
  no gateway) in `lib/engine/state/` snaps every node move to 16px
  and rejects self-loops + duplicate transitions. Drag any corner
  pin onto another node to author a transition; click a transition
  arrow to arm it (the target node renders the amber
  `▲ ARMED · {fireOn}` capsule and the arrow turns fuchsia); tap
  the armed capsule to fire — active flips to the target and every
  arm clears. Exactly one state at a time is "live" (fuchsia
  `● LIVE` capsule). Seeds `intro` (live) → `verse` on first open.
  Tapping any node also publishes it as the cross-surface selection
  (`SessionState.selection`, a `ValueNotifier<Object?>` any surface
  can write into); the selected node renders an outer fuchsia ring,
  and the right inspector swaps its placeholder for an inline-editable
  name plus a read-only three-section snapshot view (DOMAINS · CODE
  BLOCKS · SCENE REF — all empty until the time-domain / scripting /
  scene-pose layers ship).
- Unit + widget + integration tests; CI on GitHub Actions; SonarCloud
  workflow (waiting on SONAR_TOKEN)

## Surfaces

| Surface  | Status   | Folder                          |
|----------|----------|---------------------------------|
| Scene    | stub     | `lib/surfaces/scene/`           |
| Patcher  | skeleton | `lib/surfaces/patcher/`         |
| Code     | scaffold | `lib/surfaces/code/`            |
| State    | scaffold | `lib/surfaces/state/`           |
| MIDI     | editor   | `lib/surfaces/midi/`            |
| Mix      | impl     | `lib/surfaces/mix/`             |

## Where things live

- **Design source-of-truth:** `design system/colors_and_type.css` — the
  Dart tokens under `lib/design/tokens/` are derived. Hand-maintained for now.
- **Design previews:** `design system/preview/*.html` and
  `design system/ui_kits/phi-workstation/*.jsx` — open these when sketching
  new surfaces in Flutter.
- **CI:** `.github/workflows/ci.yaml` (analyze + test + coverage),
  `.github/workflows/sonar.yaml` (SonarCloud).
- **SonarCloud:** project key `yvanvds_phi`, organization `yvanvds`.
- **Issue templates:** `.github/ISSUE_TEMPLATE/`. Labels: see
  [CLAUDE.md](CLAUDE.md).

## How to start work on something

1. Read this file.
2. Read or update the relevant GitHub issue.
3. Branch from `main` as `<issue-number>-<short-slug>`.
4. Tests first where sensible (pure logic, FFI bridge code, end-to-end).
5. Open a PR; merge once CI + SonarCloud are green.
6. If this PR changed the architecture, layout, or stack, update this file.
