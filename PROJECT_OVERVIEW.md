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
  `MidiTransformChain` (ChangeNotifier). `MidiNote.pitch` is a **fractional**
  MIDI number (issue #36): `60.5` sits a quarter-tone above middle C, so a clip
  carries microtonal / just-intonation tunings through the whole chain; whole
  numbers behave exactly like the old `int` pitch. Four pitch transforms work
  end-to-end — `TransposeTransform`, `ScaleConformanceTransform` (snaps to a
  `ScaleTuning` — a cents-per-degree table, so non-12-TET scales like just
  intonation and arbitrary/non-octave tunings work; `.diatonic` builds one from
  a `MusicScale`; tie-break upward), `InversionTransform` (mirrors pitch around
  a fractional axis, keeping the fractional result), and
  `SpectralMappingTransform` (arbitrary pitch→fractional-pitch lookup table). Four time transforms follow (issue #32):
  `QuantizationTransform` (gravity-weighted snap to a beat grid — wired into
  the default chain), `StretchTransform` (scale start+duration by a factor),
  and the seedable/reproducible `HumanizationTransform` (±jitter on start and
  velocity) and `ProbabilisticSkipRepeatTransform` (per-note skip / echo
  draws) as library code awaiting UI. Three voice transforms (issue #33):
  `VoiceRoutingTransform` (ordered first-match `VoiceRoutingRule`s — pitch
  range, velocity range, or 1-based scale degree — assign `MidiNote.channel`;
  wired into the default chain as `route · osc.saw`),
  `VelocityToParameterTransform` (velocity → engine-parameter
  `ParameterEvent`s via a pure `VelocityCurve` callback — the
  `CodeEvaluator`-friendly seam; notes pass through untouched), and
  `SplittingTransform` (each note copied once per `SplitVoice` —
  channel/pitch-offset/velocity-scale layers). Three structural transforms
  (issue #34): `LoopTransform` (tiles notes across a loop window, fixed
  repeat count or fill-to-length, with a phase offset — wired into the
  default chain as `loop · 4 bars`), `ReverseTransform` (mirrors start times
  within a fixed window, preserving duration), and
  `ConditionalMutingTransform` (drops notes that fail a pure `NotePredicate`
  — the same caller-supplied-callback seam as `VelocityCurve`, standing in
  for the future state-machine/scene-volume/code-variable read) as library
  code awaiting UI. The `spawn · agent @ p,v` chip is real as of issue #37:
  `AgentSpawnTransform` (voice-family) maps each note onto an `AgentSpawn`
  (position + voice + lifetime) while passing notes through untouched — the
  same control-vs-note seam as `VelocityToParameterTransform`. Position is
  three independent `SpawnAxis`es (`lib/domain/midi/spawn_axis.dart`), each a
  clamped linear remap of a `SpawnSource` (pitch / time / velocity / channel)
  into a spatial range; voice colour derives from the note's channel, and an
  optional constant `velocity` seeds the spawn's initial drift. During
  playback `EngineMidiController` reads the chain's active spawn transform and
  drives a new `SceneAgentSink` bridge (`lib/engine/bridge/`, implemented by
  `SceneRenderer`): each note-on spawns a live `SceneAgent`, its note-off
  despawns it, and stop clears the scene — so playing the demo clip populates
  the 3D Scene. As of issue #79 spawned agents are *live participants* rather
  than static points: a pure-Dart `SceneField` (`lib/domain/scene/`) owns the
  keyed agent set and a deterministic `step(dt)` that integrates each agent's
  `SceneAgent.velocity` (`position += velocity·dt`, with a hook for the
  attraction / effect-volume / scatter forces of #80–#82). The player routes
  spawns/despawns through the field and steps it each tick, pushing the moving
  set at the sink — the demo's `+Y` spawn drift makes agents visibly rise as
  they play. The `domain · drum @ 124` chip is real as of issue #61:
  `DomainSubscriptionTransform` (time-family) resolves a `TimeDomain` by name
  through a `TimeDomainRegistry` and tempo-locks the clip to it — every note's
  start/duration is scaled by `referenceTempo / domainTempo`, so subscribing
  the 120 BPM demo phrase to `drum @ 124` compresses its beats by 120/124 (an
  unresolved name or a matched tempo is the identity). `branch · state.break`
  stays a
  `StubTransform` in the linear chain, but the branching model it points to
  now exists (issue #35): `lib/domain/midi/graph/` adds `MidiTransformGraph`
  — see below. Performers can also **author their own** transforms from the
  Code surface (issue #37→#38, the registration-seam slice): a stable
  immutable `DslNote` (`lib/domain/midi/dsl_note.dart`) is the note shape a
  live-coded `def my_transform(notes)` sees, deliberately decoupled from the
  internal `MidiNote`; a `CustomTransformDefinition` names a hot-reloadable
  `DslTransform` function; `CustomTransform` (in `transforms/`) is a
  `MidiTransform` that holds the *definition* (not the raw fn) and bridges
  `MidiNote`↔`DslNote` in `apply`; and `CustomTransformRegistry`
  (ChangeNotifier) is the catalogue the DSL registers into. Re-registering the
  same name hot-reloads the function in place, so chips already in a chain keep
  their slot and active state and just run the new logic — hot-reload preserves
  chain state. The MIDI sidebar's `+` add-transform gesture is real as of issue
  #39: the header `+` opens a menu grouping every addable transform by family
  (pitch · time · voice · struct) — the built-in `BuiltinTransformCatalog`
  (`lib/domain/midi/`) plus the registry's custom transforms — and picking one
  appends a chip with sensible defaults (callback/table-driven built-ins get a
  passthrough default the performer edits later). Chips reorder by dragging a
  handle (`ReorderableListView` → `MidiTransformChain.reorder`) and carry a
  right-click context menu: remove, duplicate (`chain.insert` places the copy
  after the original), and rename (labels now thread through
  `MidiTransform.copyWith({label})`; `CustomTransform` gains a per-chip label
  override). A full per-transform **parameter editor** is deferred (issue #39
  ships add / reorder / remove / duplicate / rename only). Real Python is still
  a `NoOpCodeEvaluator`
  (issue #9's kernel decision is open), so the live-coding→registration
  handshake runs through `FakeCodeEvaluator` (now carrying an `onEvaluate`
  hook); the shell owns a shared registry passed to both the Code and MIDI
  surfaces, and `Workstation`/`PhiApp` accept injected evaluator+registry so
  the whole flow is driveable end-to-end.
  (ChangeNotifier) — a DAG of `TransformNode`s wired by guarded
  `TransformEdge`s. Each edge carries an `EdgeCondition` (`AlwaysCondition`,
  `StateMatchCondition` on a live `PerformanceStateId`, or
  `RuntimeVariableCondition`); `evaluate([GraphEvalContext])` walks the
  subgraph whose edges are open for the current state — broadcasting a node's
  output down every open branch and merging fan-in — with `connect` rejecting
  cycles so a topological order always exists. `MidiTransformGraph.linear`
  bridges an existing chain into a degenerate DAG whose `evaluate` matches
  `MidiTransformChain.output`. The node-and-cable editor UI is real as of issue
  #65: a `CHAIN | GRAPH` toggle in the MIDI surface swaps the piano-roll area
  for a patcher-style canvas (`lib/surfaces/midi/graph/`, mirroring
  `state_canvas`) driven by a `MidiGraphController` (`lib/engine/state/`) that
  holds the graph plus node layout (positions live in the controller — the
  domain graph stays position-free) and seeds itself from the linear chain via
  `MidiTransformGraph.linear`. Nodes render the wrapped transform (kind tag +
  label + active pill); drag a node's output port onto another node to author
  an edge (the domain rejects cycles / duplicate pairs / edges into the source,
  surfaced as a banner); tap a cable to guard it (`unconditional`, a
  state-machine state, or a runtime variable). The surface feeds a live
  `GraphEvalContext` mirroring `StateGraph.activeStateId`, lights the active
  subgraph on the canvas, and re-evaluates a slim read-only piano-roll preview
  strip below — so switching the live state changes the preview. `EngineMidiController`
  owns the shared `graphController`; playback still reads the linear `chain`.
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
  chip toggles are heard immediately, not on the next play). That read is
  memoised (issue #56): the pipeline re-evaluates only when the transform
  list changes, the source clip is edited (`MidiClip.revision`, bumped by the
  edit commands and `replaceWith`), or a chip hot-reloads
  (`MidiTransform.revision`) — otherwise a read is an O(1) cache hit. The
  controller forwards
  `noteOn`/`noteOff` through a `MidiGateway` (Real over
  `package:yse`'s `MidiOut`, Fake recording calls in tests — the same
  split as `YseGateway`). An opt-in `microtonal` flag (issue #36) voices a
  note's fractional pitch as its nearest semitone plus a per-channel
  `pitchBend` (added to `MidiGateway`, ±2-semitone GM range assumed); off by
  default it just rounds. SMF export rounds fractional pitch to the nearest
  semitone (a `.mid` can't carry cents). `PhiEngine.midi` exposes it; the top-toolbar
  transport drives `play`/`stop` at `SessionState.tempo`, the piano-roll
  painter animates a non-zero playhead, and stop sends `allNotesOff`. The
  shell sources the chain/editor from `engine.midi` when present (falling
  back to its own pair when no MIDI gateway is wired). SMF import/export
  (issue #30) round-trips Standard MIDI Files through a pure-Dart codec in
  `lib/domain/midi/smf/` (`SmfReader` / `SmfWriter`, timing in quarter-note
  beats, velocity normalised): drop a `.mid` onto the surface (or use the
  header IMPORT button) to rewrite the shared clip in place — via
  `MidiClip.replaceWith` + `ClipEditor.reset` + `chain.notifySourceChanged`,
  keeping every reference intact — and the header EXPORT button encodes the
  chain's transformed `output` back to a file. The native open/save dialogs
  live behind a `MidiFileIo` seam (`FileSelectorMidiFileIo` in production,
  faked in tests) so the flow is driveable end-to-end; `desktop_drop` +
  `file_selector` own the OS shell only.
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
- Time-domains layer seed (issue #60): pure-Dart `TimeDomain` (a named
  BPM tempo reference) and an immutable, copy-on-write `TimeDomainRegistry`
  (name→domain lookup) in `lib/domain/time_domains/`. The minimal object a
  clip subscribes to and tempo-locks against — the resolution surface the
  `DomainSubscriptionTransform` binds to (issue #61, now wired into the demo
  chain). No engine bridge, tempo UI, or per-domain transport yet.
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
