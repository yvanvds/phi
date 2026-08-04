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
├── surfaces        (Scene · Patcher · Code · State · MIDI · Racks · Mix)
├── engine          (PhiEngine façade + bridge over package:yse)
├── design          (tokens + reusable widgets — no domain knowledge)
├── domain          (pure-Dart models — session/ wired; more arrives later)
├── platform        (windows-specific bits — empty for now)
└── core            (cross-cutting helpers — `Clock` wall-clock seam)
```

## Current phase

**Phase 1 — Audio hello-world + workstation chrome.** Implemented:
- Design tokens (colors, type, spacing, motion, radii) in `lib/design/tokens/`
- Theme in `lib/design/theme.dart`
- Widget library: `PrimaryButton`, `PeakMeter`, `Capsule`, `PhiToggle`,
  `InlineEditableText`, `TransportButton`, `RailButton`, `StatusChip`,
  `PhiFader`, `ChannelStrip`, `PhiSelect` (token-first dropdown — flat or
  host-grouped options, keyboard nav, disabled state; issue #153) +
  `PhiChecklistRow` (label + checkbox + trailing slot)
- `PhiEngine` façade over a `YseGateway` interface (`RealYseGateway` for
  production, `FakeYseGateway` for tests). Owns the master + N user
  `MixerChannel` instances and exposes add/remove/volume/mute/solo;
  mute/solo are collapsed to an effective gateway volume since YSE has no
  native notion of them. Since issue #150 `YseGateway` also carries the
  **device surface** the settings epic (design `settings-and-devices.md`)
  consumes: `audioDevices()` hands out FFI-free `AudioDeviceDescriptor`s (name +
  host identity, reported rates/buffers/latencies), `openAudioDevice()` does the
  `initOffline` boot / `closeCurrentDevice`+`openDevice` live-swap (throwing a
  bridge-level `AudioDeviceException` the caller falls back on), and
  `activeAudioState()` reads back the live device state — the `SpeakerLayout`
  domain enum maps to yse's `ChannelType` only inside the bridge.
- `SessionState` in `lib/domain/session/` — pure-Dart cross-cutting state
  (transport intent, projection, scene name)
- Workstation chrome: top toolbar (wordmark, inline-editable scene name,
  play/stop transport, time-domain placeholder, projection toggle), left
  rail (6 buttons, only Mix enabled), bottom status (LIVE dot, CPU + drops),
  right inspector (tap to expand 28→320px, hosts a master-volume fader)
- Shell layout — dockable single-instance surfaces in a split tree (design
  `docs/design/shell-layout.md`, epic #249). The pure-Dart layout domain
  (`lib/domain/shell_layout/`, issue #250) — `ShellLayout` over a `LayoutNode`
  split tree of tab-stack `LayoutPane`s + `LayoutSplit`s, with split / join /
  move / reorder / activate / close / resize ops, fraction geometry, JSON
  round-trip and fit-fallback. Issue #251 wired it into the centre: a shell-side
  `ShellLayoutController` (`lib/shell/layout/`, `ChangeNotifier`) owns the tree +
  the active pane and turns the **rail into identity + summon** (a tap focuses a
  surface wherever it is docked, or opens it in the active pane if closed);
  `SplitTreeView` renders the tree into nested rows/columns and `SurfacePane`
  renders each pane's resident tab stack (active tab paints, others stay mounted
  offstage). Each surface is wrapped in a stable `GlobalKey` so a **dock move
  re-parents its element rather than rebuilding it** — its state survives the
  move; Scene stays the exception (mounted only while it is the visible tab, GL
  re-parenting verified by hand). Behaviour-neutral default: one pane, Mix open —
  the app looks identical until the performer splits (drag-to-dock UI + tab
  strips are #252). `Workstation`/`PhiApp` accept an injected controller so a
  dock move is driveable end-to-end. Issue #253 persists the arrangement in the
  **project manifest** (`ProjectManifest.layout`, journal-free): the
  `ProjectController` owns the `ShellLayout` as manifest state — the shell's live
  controller pushes edits in through `ProjectController.updateLayout` (dirties
  the manifest so save/autosave picks it up, but never journals and is not
  undoable), and on New/Open the controller bumps a `layoutRestored` signal the
  shell listens to, adopting the restored layout into its live controller with
  `ShellLayout.fit` (clamps splitter fractions, drops unknown surfaces). Recovery
  replay never touches it — layout is workspace arrangement, not authored
  content, so the manifest's last save wins (design §3, §7 decision 1).
  Issue #254 adds the **command registry + palette overlay** (`lib/shell/commands/`,
  design §4). A `PhiCommand` value type (id · title · category · optional
  `CommandShortcut` · enabled-predicate · `invoke`) is registered into a
  `CommandRegistry` (ChangeNotifier) the workstation seeds with the shell commands
  — surface summon (one per rail identity), transport play/stop (enabled-gated on
  the transport state), projection toggle, and, when the project stack is wired,
  project ops + settings — each `invoke` reusing the *exact* callback the
  rail/toolbar/menu already runs, so the palette is a launcher, never a second
  implementation. `CommandRegistry.invoke` routes execution and records recents;
  `shortcutBindings()` exposes the default map as `{ShortcutActivator:
  VoidCallback}` for issue #255 to fold the app's bindings in. A pure `CommandSearch`
  (`command_search.dart`, no Flutter) ranks a query: empty → every enabled command
  recents-first then registration order; non-empty → a subsequence fuzzy match over
  title (then, weaker, category) rewarding contiguous runs + word-starts, best score
  first, ties toward the more recently used. `CommandPalette` is the Ctrl+Shift+P /
  F1 overlay (`showDialog`, top-anchored) — an autofocused field whose focus-node
  `onKeyEvent` intercepts arrows/enter/escape ahead of the text editing shortcuts,
  disabled commands hidden, matched glyphs highlighted, the shortcut chord shown per
  row. `Workstation`/`PhiApp` accept an injected registry; the shell owns one
  otherwise. Covered by unit tests (registry, pure search, shortcut label/activator),
  a `CommandPalette` widget test (open · filter · disabled hidden · keyboard nav ·
  Enter/tap invoke · recents float · shortcut render), and an end-to-end
  `command_palette` integration test (Ctrl+Shift+P → filter → Enter summons MIDI;
  play then reopen shows the now-enabled Stop; F1 opens).
- Settings dialog (`lib/shell/settings/`, design `settings-and-devices.md`
  §6, issues #154 + #151): a modal overlay (no rail button, no OS window) opened
  from the File menu's `Settings…` item, with a left section list (AUDIO · MIDI ·
  PROJECTS · DIAGNOSTICS) and no OK/Cancel — every control applies immediately.
  All four sections now carry fields:
  - **AUDIO**: `PhiSelect` pickers for output device (grouped by host), sample
    rate + buffer size (from the *selected* device's reported lists, "device
    default" first), and speaker layout, plus a live read-back of the active
    rate / buffer / latency. Each change goes through `PhiEngine.switchAudioDevice`
    (the live-switch path); on success the new `AudioSettings` persists through the
    single `AppSettingsController` (§7), on failure the coordinator reverts to the
    previous working device and the picker snaps back (§9.3). `PhiEngine` exposes
    `audioDevices()` / `activeAudioState()` so the dialog reaches the device
    surface without touching the gateway.
  - **MIDI** (`midi_settings_section.dart`): an output-port `PhiSelect` (stored by
    name) and an input-port `PhiChecklistRow` list with a per-port `MidiActivityDot`.
    Changes persist through `AppSettings.withMidi` and push to `PhiEngine.applyMidiSettings`,
    which sets the player's output-port *name* (`EngineMidiController` resolves it to
    a device index each open, so a replug keeps working — replacing the old hard-coded
    port 0) and opens the enabled input ports. `PhiEngine` exposes `midiOutputPorts()` /
    `midiInputPorts()` / `midiInputActivity`.
  - **PROJECTS** (`projects_settings_section.dart`): an autosave-cadence field
    (`0` disables; `AppSettings.withAutosaveInterval`, applied on the next timer arm —
    `ProjectController` re-arms/disables) and recents management — per-entry remove,
    clear-all, and pin/unpin (`withoutRecentProject` / `withClearedRecents` /
    `withPinnedProject`). Pins float above recents in the File menu (mirrored via the
    controller's new `pinnedProjects` notifier), so a pin/remove shows there at once.
  - **DIAGNOSTICS** (`diagnostics_settings_section.dart`): read-only rows — libYSE
    version, resolved `YSE_DLL_PATH`, active device + host, audio-stall counter —
    with a copy button that writes a paste-ready block. Fed by
    `PhiEngine.engineVersion` / `engineLibraryPath` / `audioStalls`.

  Covered by unit (`AppSettings`/`MidiSettings` copy-withs, `EngineMidiController`
  output-port-by-name re-resolution), widget (each section's apply/persist + the
  dialog shell), and end-to-end `settings_dialog_audio` + `settings_dialog_sections`
  integration tests (open from the File menu → drive each section → persisted).
- Mix surface: horizontal rack of `ChannelStrip` widgets (master pinned
  right, user strips left). Header has a `+` to add channels and the
  `System.audioTest` toggle. Each strip carries voice-swatch + name + fader
  with overlaid peak meter + mute/solo buttons. A user strip's header name is
  inline-editable and carries a `×` remove control (issue #141) — the master
  strip has neither. Beneath each leaf strip and group-bus header sit an
  **INSERTS** area (the ordered `fx.` insert chain — place / reorder / remove /
  move-with-impact, issue #212) and a **SENDS** area (aux sends to return buses);
  see the racks-epic and mix-epic entries below.
- Scene surface: renderer-agnostic `SceneRenderer` bridge in
  `lib/engine/bridge/`, backed in production by `MacbearSceneRenderer`
  (`macbear_3d` on ANGLE). Renders one placeholder agent as a
  voice-coloured sphere; orbit/pan/zoom via macbear's built-in controller.
  Pointer picking + grab landed with issue #86 (surface half of #82): a
  `PhiScenePickController` (`M3InputController`) unprojects the pointer into a
  world `PickRay` via the pure `SceneUnproject` (screen→world math over the
  live camera's view/projection matrices), asks `SceneField.pick` which agent
  sits under it, and — on a hit — selects + grabs it (drag → `moveGrabTo` on a
  camera-facing plane at the agent's depth → `releaseGrab`), delegating misses,
  right-drag pan, scroll zoom, and keyboard nav to a fallback orbit controller.
  The Scene surface implements the renderer-agnostic `ScenePickHandler` seam
  (forwarding pick/grab to `EngineMidiController`, which owns the shared field,
  so mouse and code grab the same agents) and owns selection: a bright
  translucent halo (`PhiMacbearScene.setSelection`) tracks the picked agent's
  live position, refreshed by the surface's own gated ticker. Field *motion*,
  though, is stepped by the player's one frame ticker in all cases as of issue
  #103 — a grab starts that ticker even on a stopped transport — so the surface
  no longer owns a separate `stepFromSurface`, and the old play/stopped stepping
  split is gone. The GL
  viewport can't be exercised headless (no ANGLE context in CI), so the pure
  math, the input controller, and the surface wiring are unit/widget-tested
  behind fakes and the pointer path is verified manually. Issue #90 adds a
  debug-only **pick demo** toggle on the Scene surface: the playback demo's
  notes are too short and clustered to click by hand, so flipping the toggle
  calls `EngineMidiController.loadSceneDemo` — seeding a handful of long-lived,
  well-separated static agents (`pickDemoAgents`, `lib/domain/scene/`) into the
  shared field so pick/select/grab can be exercised at leisure; toggling off
  (or a transport stop) clears them.
- Code surface: `re_editor`-backed Python editor with custom
  Phi-flavoured highlight theme, projected view (full-line comments
  stripped, blank-line runs collapsed) driven by
  `SessionState.projection`, and Ctrl+Enter dispatching the block under
  the cursor to a `CodeEvaluator` abstraction. Issue #232 makes it real:
  `RealCodeEvaluator` runs blocks through the engine's embedded CPython
  (`LiveCoding.run`) and republishes `LiveCoding.errors` as `EvalStderr`
  frames; the app wires it in production when the build has Python
  (`buildCodeEvaluator()` gated on `LiveCoding.enabled`), falling back to
  `NoOpCodeEvaluator` otherwise (tests keep the no-op default). The header
  carries a **`fresh` toggle** (off by default — layering; on prefixes each
  evaluation with `yse.cancel_all()`) with a visible mode indicator, and an
  inline **traceback strip** pinned under the editor renders the newest
  Python error verbatim (`PythonTraceback` parses the `"<script>"` line),
  turning the eval flash red when it maps onto the just-run block —
  callback-origin tracebacks (no matching editor line) still render. The
  `RealRegistryMirror` production wiring (live `phi` name table) is deferred
  to #314. Issue #235 gives scripts a home in the registry: a new `code.`
  entity kind whose payload is a `CodeScript` (source text under one `source`
  key; `lib/domain/code/`, `CodeScriptCodec` at schema v1, registered in
  `defaultEntityCodecs`) — so a saved script reopens byte-identical, and the
  `phi` library models no `code` namespace (the mirror silently ignores the
  kind). A fresh project is seeded with `code.scratch` (its source the shared
  `codeScratchSource`, also the surface's project-less fallback) so the editor
  is never empty. A **script library panel** (`CodeLibraryPanel`, mirroring the
  MIDI clip library, minus play/loop) docks on the Code surface's left, driven
  by a `CodeLibraryController` (`lib/engine/state/`, ChangeNotifier over the
  `code.` namespace): the tree, new / duplicate / rename-refactor / delete
  (+ groups, drag-regroup / reorder — the usual registry affordances via the
  journaled command layer), and **select-to-open** (the editor swaps its content
  to the picked script; an in-flight edit to the previous one is flushed first —
  the ordinary dirty-tracking guard). Edits are **coalesced per idle pause**:
  typing restarts a debounce, and the settled burst journals one
  `UpdateEntityPayloadCommand` (de-duped by content), never one per keystroke.
  Evaluation is unchanged — what has been evaluated is performance state, never
  persisted. The surface takes an optional `libraryController`; without one (the
  bare Phase-1 path) it stays a single seeded buffer with no panel. Covered by
  unit (`CodeScript`, `CodeLibrary` + byte-identical save/load round-trip,
  `CodeScriptCodec`), controller, and `CodeLibraryPanel` widget tests, plus an
  end-to-end `code_library` integration test (scratch shows → add a script →
  type → save → a second launch restores the source verbatim; selection swaps
  the editor content). Issue #236 adds **registry-driven completion** (no LSP):
  a pure-Dart `PhiCompletionResolver` (`lib/domain/code/completion/`) turns the
  text left of the cursor into rows — a `phi` namespace + dot (`voice.`) lists
  that kind's entities and groups from the live registry (Phi-flavoured: voice
  colour tokens, clip bar-lengths, group markers), a group dot (`clip.drums.`)
  narrows to its members, and an entity dot (`voice.bells.`) offers a **static
  method table** (`phiMethodTable`, a checked-in artifact mirroring the `phi`
  library's `_VERB_NAMES`, guarded by a drift test); a non-`phi` line resolves to
  `null` so plain Python typing is untouched. It hosts in `re_editor`'s
  autocomplete hook via a `PhiCompletionPromptsBuilder` + a `PhiCompletionListView`
  overlay (`lib/surfaces/code/completion/`, keyboard nav + identifier-only
  insertion), wired into `CodeEditorView` from the engine's live registry.
  Covered by resolver unit tests, the drift guard, prompts-builder / list-view /
  editor-wiring widget tests, and an end-to-end `code_completion` integration
  test (real seeded project → each namespace resolves its real entities, a leaf
  the method table, a plain line nothing).
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
  range, velocity range, or 1-based scale degree — assign `MidiNote.voice`, a
  `voice.` registry address string (issue #205); wired into the default chain as
  `route · voice.default`), `VelocityToParameterTransform` (velocity →
  engine-parameter `ParameterEvent`s via a pure `VelocityCurve` callback — the
  `CodeEvaluator`-friendly seam; notes pass through untouched), and
  `SplittingTransform` (each note copied once per `SplitVoice` —
  voice/pitch-offset/velocity-scale layers). Three structural transforms
  (issue #34): `LoopTransform` (tiles notes across a loop window, fixed
  repeat count or fill-to-length, with a phase offset — wired into the
  default chain as `loop · 4 bars`), `ReverseTransform` (mirrors start times
  within a fixed window, preserving duration), and
  `ConditionalMutingTransform` (drops notes matching a declarative
  `NoteCondition` — a leaf `NoteFieldCondition` (field · comparison ·
  threshold over pitch/velocity/start — the note's voice is an address, not a
  comparable scalar, so it is not a field) or an `all`/`any`
  `NoteConditionGroup` of them; issue #109 replaced the bare `NotePredicate`
  callback with this serialisable model, keeping `NotePredicate` only as the
  evaluated keep-form, and still standing in for the future
  state-machine/scene-volume/code-variable read). The `spawn · agent @ p,v` chip is real as of issue #37:
  `AgentSpawnTransform` (voice-family) maps each note onto an `AgentSpawn`
  (position + voice + lifetime) while passing notes through untouched — the
  same control-vs-note seam as `VelocityToParameterTransform`. Position is
  three independent `SpawnAxis`es (`lib/domain/midi/spawn_axis.dart`), each a
  clamped linear remap of a `SpawnSource` (pitch / time / velocity / voice —
  the voice folded into a stable bucket by `voice_hash.dart`) into a spatial
  range; voice colour derives from the note's routed voice, and an optional
  constant `velocity` seeds the spawn's initial drift. During
  playback `EngineMidiController` reads the chain's active spawn transform and
  drives a new `SceneAgentSink` bridge (`lib/engine/bridge/`, implemented by
  `SceneRenderer`): each note-on spawns a live `SceneAgent`, its note-off
  despawns it, and stop clears the scene — so playing the demo clip populates
  the 3D Scene. As of issue #79 spawned agents are *live participants* rather
  than static points: a pure-Dart `SceneField` (`lib/domain/scene/`) owns the
  keyed agent set and a deterministic `step(dt)` that integrates each agent's
  `SceneAgent.velocity` (`position += velocity·dt`). The player routes
  spawns/despawns through the field and steps it each tick, pushing the moving
  set at the sink — the demo's `+Z` spawn drift makes agents visibly rise as
  they play (the scene camera's up axis is `+Z`, so `+Z` reads as up on
  screen; issue #89). Issue #80 adds **effect volumes**: an `EffectVolume` is a spatial
  region (`SphereVolume` or AABB `BoxVolume`) carrying a named effect + a send
  amount; the field holds a set of them and, each `step`, recomputes every
  agent's `SceneAgent.sends` (effect tag → amount) from its new position, so an
  agent picks up or drops a send as it drifts across a boundary. This is a
  *send* the DSP layer will later route, not a velocity force — the actual
  engine-bridge wiring (consuming `sends` into real effect routing) is a separate
  slice. `EngineMidiController` exposes `addEffectVolume` / `removeEffectVolume` /
  `clearEffectVolumes` / `effectVolumes` (issue #93), so the spawn→scene path
  routes spawned agents through placed volumes and volumes outlive a transport
  stop; pointer placement still waits on the Scene surface graduating.
  Issue #81 adds **scatter**: a `Scatter` (`lib/domain/scene/`) is a one-shot,
  seedable, bounded random impulse that kicks every live agent's position (and
  optionally velocity) apart; `SceneField.scatter` applies it in-place keeping
  keys, and `EngineMidiController.scatter` exposes it as a one-shot performer
  action that disperses the live set and pushes the throw to the sink — the UI
  trigger waits on the Scene surface graduating. The `domain · drum @ 124` chip is real as of issue #61:
  `DomainSubscriptionTransform` (time-family) resolves a `TimeDomain` by name
  through a `TimeDomainRegistry` and **binds the clip's transport clock** to it.
  Since issue #102 the subscription is a *clock choice, not a note rewrite*: it
  is the identity on the note stream and exposes `boundTempo`, which
  `EngineMidiController` runs the transport's domain clock at while the chip is
  active (the session tempo when unsubscribed) — so subscribing the demo phrase
  to `drum @ 124` plays it at 124 BPM without moving a single note beat, and a
  live tempo change never forces a re-push (`docs/timing-architecture.md` §4).
  An unresolved name binds nothing (`boundTempo == null` → the session tempo).
  `branch · state.break` stays a
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
  after the original), rename (labels now thread through
  `MidiTransform.copyWith({label})`; `CustomTransform` gains a per-chip label
  override), and **edit parameters…** (issue #71): every scalar transform
  exposes its editable params as `TransformParam` descriptors
  (`lib/domain/midi/transform_param.dart` — sealed `IntParam`/`DoubleParam`
  with optional bounds) plus a `MidiTransform.withParam(name, value)` mutation
  seam, and `TransformParamEditor` (`lib/surfaces/midi/`) renders one field per
  descriptor, applying each parse-valid keystroke live through
  `MidiTransformChain.replaceAt` so ghost and playback follow while the dialog
  is open. The five table/rule-list transforms (spectral map, routing rules,
  split voices, spawn axes, scale tuning) don't fit that scalar seam, so
  issue #95 gives each a dedicated **typed editor** under
  `lib/surfaces/midi/param_editors/` (a shared field vocabulary in
  `editor_fields.dart`, one dialog per family, dispatched by
  `typed_param_editors.dart`); each mutates the chip in place through the
  transform's own `copyWith({…data field…})` — again live via
  `MidiTransformChain.replaceAt`. Issue #108 graduated the velocity→parameter
  transform into that same typed-editor set: its bare `double Function(double)`
  callback is now a declarative, serialisable `VelocityCurve`
  (`lib/domain/midi/transforms/velocity_curve.dart`) — a pure, immutable
  value-type carrying a `VelocityCurveShape` (linear / exponential / logarithmic
  / stepped) and an output range `[valueAt0, valueAt1]`, evaluated in
  `eventsFor`; a `VelocityCurveEditor` reshapes it live from the chip menu, so
  the catalogue's identity-curve default becomes meaningful through editing
  alone. Issue #109 did the same for the muting predicate: its bare
  `NotePredicate` callback is now a declarative `NoteCondition`
  (`lib/domain/midi/transforms/note_condition.dart`) — a leaf
  `NoteFieldCondition` or an `all`/`any` `NoteConditionGroup` — and a
  `NotePredicateEditor` builds it live from the chip menu, so no transform is
  callback-driven any more. Real Python is still
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
  state-machine state, or a `var · name = value` runtime variable). Those
  variables come from a `RuntimeVariableRegistry` (`lib/domain/runtime/`,
  ChangeNotifier) — the store #78 added to close the loop #65 left open: a
  `RuntimeVariable` is an *enumerated* choice (name + candidate string values +
  current), so the picker offers concrete guards instead of the old free-text
  stub, and a guard can only ever name a value the variable can actually take
  (value type settled as string — stable, hashable, `==`-comparable). The engine
  owns the registry (like the `StateMachine`) and a graph-mode **variables bar**
  (`lib/surfaces/midi/graph/runtime_variables_bar.dart`) defines variables and
  flips their value live. The surface feeds a live `GraphEvalContext` mirroring
  **both** `StateGraph.activeStateId` and the registry's current values
  (`snapshot()`), lights the active subgraph on the canvas, and re-evaluates a
  slim read-only piano-roll preview strip below — so switching the live state
  *or moving a variable* changes the preview. A clip is
  **either** a linear (chain) or branching (graph) clip — its
  `MidiClipMode` (`lib/domain/midi/`) — and you move between them by
  **conversion**, not a casual toggle (issue #77). Chain is the default: the
  piano roll edits the source, the `TRANSFORM CHAIN` sidebar manages the linear
  transforms, and a `convert to graph` action (behind a `ConfirmDialog`,
  `lib/design/widgets/dialog/`) re-seeds the graph from the *current* chain
  (`MidiGraphController.loadFromChain`) and flips the mode. Graph mode drops the
  sidebar and shows `NOTES | GRAPH` tabs — the roll stays a first-class editor
  (you never leave graph mode to edit notes) while the canvas gets the full
  width — plus a `convert to chain` action that warns before dropping branches
  when the graph is no longer `MidiTransformGraph.isLinear`, writing the
  extracted spine (`linearTransforms`) back via `MidiTransformChain.setTransforms`.
  Playback follows the mode: `EngineMidiController` owns the shared
  `graphController`, holds the `StateGraph` and `RuntimeVariableRegistry` for the
  live context, and reads the chain's `output` or `graph.evaluate(context)`
  accordingly — so a state- or variable-guarded branch re-routes the *sounding*
  notes as the live state flips or a variable moves, not just the preview. The linear chain stays the zero-overhead default;
  `MidiTransformGraph.evaluate` is memoised the same way the chain is (below),
  the cache keyed additionally on the eval context so a state flip recomputes
  once, not every tick.
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
  chain + editor. **Since issue #101 note dispatch belongs to the engine, not
  the UI isolate** ([timing-architecture.md](timing-architecture.md) §2): on
  `play` the controller flattens the chain's transformed `output` into a
  `TransportNote` list and **pushes** it (plus the loop length) to a
  `MidiTransport` bound to a domain clock, and the engine fires every note from
  the audio thread. A frame ticker still runs, but only for the display
  playhead and the Scene agent field — **both now queries of the engine clock**
  (issue #103): each tick reads the transport's `beatPosition` (the audio-thread
  integral of tempo) and derives the playhead and the Scene-spawn window from it
  rather than integrating a Dart accumulator, so display and visuals track the
  notes actually sounding even under UI jank; stop rewinds through the
  transport's stopped state. The same tick also **re-pushes on change**: the
  `output` read is memoised (issue #56), so it hands back a *fresh list
  instance* only when the transform list changes, the source clip is edited
  (`MidiClip.revision`, bumped by the edit commands and `replaceWith`), a chip
  hot-reloads (`MidiTransform.revision`), or — graph mode — a state/variable
  flip re-evaluates; the tick detects the new instance and re-pushes, so "read
  every tick" became "push on change" and an edit is heard within one audio
  block with UI jank out of the timing path. `MidiTransport` (Real over
  `package:yse`'s `DomainClock` + `ClipTransport`, Fake recording the pushed
  events in tests) is minted by `MidiGateway.createTransport`; the gateway's own
  surface shrank to the genuinely immediate MIDI — device enumeration, opening
  the port, and `allNotesOff` on stop (the same Real/Fake split as `YseGateway`).
  Issue #150 grows `MidiGateway` with the **input** surface the settings epic
  needs: name-addressed input enumeration, `openInputs`/`closeInputs` of the
  enabled ports, and an `inputActivity` stream ticking the receiving port's name
  for the UI dot — the hardware is opened and its activity shown, but nothing
  routes MIDI-in anywhere yet (that is the racks & voices epic).
  An opt-in `microtonal` flag (issue #36) voices a
  note's fractional pitch as its nearest semitone plus normalised pitch-bend
  event data the transport carries (±2-semitone GM range assumed); off by
  default it just rounds, and flipping it while playing re-pushes. SMF export
  rounds fractional pitch to the nearest
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
  chain's transformed `output` back to a file. **Note:** note dispatch has
  migrated to the engine clip transport (issue #101,
  [timing-architecture.md](timing-architecture.md) §2) — the UI isolate no
  longer times notes; the chain/graph interpretation layer stays in Dart and
  pushes revision-keyed note lists to the transport instead of dispatching them
  tick-by-tick. Scene spawn re-anchoring and the playhead as an engine-clock
  query landed with issue #103 (§4); still Dart-side and slated to follow:
  playable/ramped domain tempo (§3). Issue #82 adds
  the **domain-side
  grab** (direct-manipulation pull): `SceneField` holds a grabbed key + a held
  target and, inside `step`, pulls the held agent `grabStrength` of the way to
  the target each tick — carrying that displacement as velocity, so `release`
  throws a moving grab and lets a settled one rest. A pure `PickRay`
  (`lib/domain/scene/pick_ray.dart`) + `SceneField.pick` ray/sphere hit-test
  resolves which agent sits under a ray, and `EngineMidiController` exposes
  `pick` / `grab` / `moveGrabTo` / `releaseGrab` as code-drivable performer
  actions — so code grabs exactly as the mouse will. The macbear surface half
  (pointer picking, selection highlight, custom input controller) is split into
  #86 (needs the GL viewport; not CI-testable). The native open/save dialogs
  live behind a `MidiFileIo` seam (`FileSelectorMidiFileIo` in production,
  faked in tests) so the flow is driveable end-to-end; `desktop_drop` +
  `file_selector` own the OS shell only.
  MIDI **recording** (design `docs/design/midi-recording.md`, epic #259) begins
  with the capture spine (issue #260): a pure-Dart `TakeRecorder`
  (`lib/domain/midi/record/`) turns live MIDI-in into a clip's *source* notes.
  Driven by injected note-on/off calls + an injected beat-clock reader (no
  engine, no UI — that wiring is #261), it pairs on/off by pitch into `MidiNote`s
  stamped straight off the clock (**raw always** — pitch as played, velocity
  normalised, no snapping; design §2 / §8 decision 1), tags each with the armed
  `voice` (§8 decision 3), edge-closes notes held at **stop** (at the stop beat)
  and across a **loop wrap** (closed at `MidiClip.totalBeats`, reopened at beat 0
  as a new note), drops orphan note-offs, and commits **each loop pass as one
  batch** through the ordinary clip-edit command layer (a bare `AddNoteCommand`,
  or a `CompositeClipCommand` for a multi-note pass) so Ctrl+Z removes a whole
  pass. Pure-domain, unit-tested against a fake keyboard + fake clock.
  Issue #261 wires it into the editor as the **record arm + capture flow**: a
  `RecordController` (`lib/engine/state/`, ChangeNotifier) holds the record-arm
  flag (performance state, never persisted) and drives a `TakeRecorder` against
  the edited session through a small `RecordTarget` seam (which `ClipSession`
  implements — source clip · undo scope · `autoExtend` · address · play-relative
  beat). It subscribes to the gateway's parsed MIDI-in, so **arm + play** starts
  a take, **arming while playing** punches in, and **stop or disarm** ends it
  (keeping the notes); each finished pass commits through the clip's `UndoScope`
  so the ordinary revision bump refreshes the ghost / re-pushes playback live and
  Ctrl+Z peels passes newest-first. The engine's frame ticker fires the pass
  boundary: with **auto-extend off** the loop wraps and passes overdub; **on**,
  the clip grows to contain the take (the length grow journaled *with* the notes,
  one undo). Recorded notes carry the racks audition path's **armed voice**
  (monitoring is that same path — no extra plumbing). A record button joins the
  editor transport row (`ClipTransportRow`), lit while armed/recording. Covered
  by `RecordController` unit tests (fake session/clock/input — arm+play, punch-in,
  overdub + undo peeling, auto-extend grow/wrap, armed-voice tagging, live ghost),
  a `MidiSurface` record widget test, and an end-to-end `midi_record_arm`
  integration test (arm → play → a played note lands in the clip → undo).
  Issue #262 adds the **metronome** — the click to record against (design §4).
  A pure-Dart `ClickPattern` (`lib/domain/metronome/`) generates a one-bar click
  per meter (`beatsPerBar` + downbeat `accent`) as `ClickBeat`s. A
  `MetronomeController` (`lib/engine/state/`, ChangeNotifier) turns it into a
  **click session** built on the ordinary transport machinery: it mints a
  `MidiTransport` on its own reserved clock (`phi.metronome`), pushes the pattern
  flattened into `TransportNote`s (looping the meter) and lets the engine
  dispatch every click — paced from the **bound domain's tempo** (the session
  tempo when none is bound), so switching the domain, or editing the bound
  domain's tempo (`refreshDomains`), re-paces the running click without ever
  re-pushing the note list. The click plays a reserved, seeded **click voice** —
  a sine synth `PhiEngine` materialises **lazily** on first enable, on a reserved
  channel routed to master, and connects the click transport to (a project that
  never clicks pays nothing, and the racks stay untouched). Click state is
  performance state — enabled / domain / meter / accent / volume — never
  persisted, so a loaded project starts silent. The toolbar `MetronomeControl`
  (`lib/shell/top_toolbar/`) replaces the domain-summary placeholder: a click
  toggle plus a popover (`MetronomePopover`) with a `PhiSelect` over the `domain.`
  entities, beats-per-bar, the accent toggle, and a volume slider. Covered by
  `ClickPattern` unit tests (per meter, accent placement), `MetronomeController`
  unit tests (enable/disable, domain re-binding + tempo re-pacing via
  beat-position math, meter/accent/volume re-push, click-voice connect), an
  `engine_metronome` wiring test (lazy click-synth materialisation on master), a
  `MetronomeControl` widget test (toggle + popover controls), and an end-to-end
  `metronome_click` integration test (toolbar enable → bind `drum @ 124` →
  re-pace → change meter → stop).
  Issue #263 adds the **count-in** (design §5) — an N-bar delay before a fresh
  play/record. A `CountInController` (`lib/engine/state/`, ChangeNotifier) holds
  the count length in bars (`0 / 1 / 2`, performance state, never persisted) and
  schedules the wait as a **query of the engine clock** each frame — no Dart
  timer in the timing path: [begin] captures the clock's beat as the origin and
  the count completes once it advances `bars × beatsPerBar` beats, firing a
  downbeat callback (audio-agnostic — the click counts when enabled, a silent
  wait when not; the schedule is identical). `EngineMidiController.play` gates a
  **fresh** start on it: with `bars > 0` it mints/paces a reserved count clock
  (`phi.midi.countin`) at the edited session's tempo and, at the clip's meter,
  waits before starting the session and any armed take on the downbeat; a stop or
  pause aborts the count cleanly, and a punch-in into an already-running session
  never waits (only a fresh play is scheduled). The toolbar `MetronomePopover`
  gains a count-in `PhiSelect` (off / 1 bar / 2 bars) bound to the controller.
  Covered by `CountInController` unit tests (scheduling at several meters, origin
  capture, abort, no-op guards), `EngineMidiController` fake-clock tests (the
  waited start, capture beginning on the downbeat, stop-abort, punch-in bypass,
  0-bar immediate, meter-driven length), a `MetronomeControl` widget test (the
  picker), and an end-to-end `count_in` integration test (set count-in → play
  waits → stop aborts).
  Issue #264 adds **panic** (design §6) — the one unmissable, idempotent
  stop-everything. `EngineMidiController.panic` ends any armed take **keeping its
  notes** (the held notes close at the current beat and commit as authored
  content, done before the transports rewind so the beat is real), aborts a
  running count-in, stops every clip session (each rewinding and clearing its own
  scene agents), then — beyond the per-session stop — all-notes-off the MIDI-out
  port and every materialised voice synth (releasing a held arm-for-input / test
  strip audition the transport never dispatched — `MaterialisedSynth.allNotesOff`,
  a thin wrap of yse's `Synth.allNotesOff`) and clears every remaining live scene
  agent (the whole field, so pending spawns despawn). `PhiEngine.panic` composes
  that with stopping the click and silencing the reserved click voice; every step
  is idempotent, so a double-panic is a no-op. The shell surfaces it three ways
  that share one code path (`PhiEngine.panic` plus a toolbar-transport reset): a
  `PanicButton` in the bottom status right of the `LIVE` dot, a permanent `F12`
  shortcut, and a `transport.panic` palette command (design shell-layout §4).
  Covered by `EngineMidiController` panic unit tests (the four steps against
  fakes, take-note survival, idempotency), `PhiEngine` panic tests (click stop +
  click-voice silence, session stop + port all-notes-off, before-start no-op), a
  `BottomStatus` widget test (the button runs `onPanic`), a `shell_commands` test
  (the permanent F12 Transport command), and an end-to-end `panic` integration
  test (F12 and the button each stop the click, the session, and the transport).
- State surface: pan/zoom canvas (reuses the patcher's 16px dot grid
  backdrop) of rounded-square state nodes with four voice-coloured corner
  pins, plus directed transition arrows drawn as cubic Béziers between the
  closest source/target edges with arrowheads. Since issue #241 the canvas is
  **registry-backed**: nodes are `state.` entities, and the
  `StateMachineController` (`lib/engine/state/`) fronts the registry — the
  view rows (`StateNodeData`) and edges (`StateTransition`, both
  `lib/domain/state_machine/`) derive from the entity payloads on every
  change, and every structural edit (add / duplicate / rename / delete /
  connect / disconnect / node move) is a journaled command through the
  ordinary create/move/remove/update-payload command layer, so it dirties,
  saves, and undoes like any other project change. Node drags stay transient
  while the pointer is down (16px snap as always) and commit **one** position
  command on release. Which state is **live** and which transitions are
  **armed** are performance state keyed by entity address — never persisted;
  a loaded or reloaded project re-seeds live on its first `state.` entity.
  **Rename = refactor**: a rename is a registry move, sibling transition
  targets rewrite in the same command, live/armed/drag references remap in
  place (rename mid-arm keeps the arm), and the controller's `onStateMoved`
  hook has the engine repoint every open MIDI session's `state.` guards
  (`EngineMidiController.repointStateGuards`) so guard evaluation re-routes
  live. Standard affordances ride context menus: right-click empty canvas →
  *new state* at that spot; right-click a node → *duplicate* / *delete* (the
  latter behind the delete-impact dialog when other entities still point at
  the state; deleting also clears inbound transitions as journaled payload
  updates). Drag any corner pin onto another node to author a transition;
  click a transition arrow to arm it (the target renders the amber
  `▲ ARMED · {fireOn}` capsule); tap the armed capsule to fire — live flips
  to the target and every arm clears, journal-free. Exactly one state is live
  whenever any exists (fuchsia `● LIVE` capsule). `PhiEngine.start` seeds the
  default `intro → verse` pair into its own scratch registry when no project
  is bound (bare engine, tests); a bound project's states are authored
  content (`state_seed.dart` seeds fresh projects), and `bindRegistry`
  rebinds the controller so New/Open re-render the canvas and re-seed the
  live capsule. Tapping a node publishes a `StateEntitySelection`
  (controller + address + the runtime-variable registry) into
  `SessionState.selection`; the right inspector
  renders the entity — inline rename through the journaled refactor
  (re-publishing the selection at the new address), the dotted address, and
  the full SLICES / ON ENTER / TRANSITIONS panels (issue #245, below).
  Covered by the controller
  suite (journaled edits, arm/fire, rename-refactor + undo, delete impact,
  rebind), canvas + inspector widget tests (context menus, impact dialog,
  selection, rename re-publish, stale-selection fallback), and the
  `state_graph_canvas` integration test (drag journals the position, rename
  mid-arm keeps the arm on-screen, context-menu new state, save + second
  launch restores the graph, the positions, and the live-state seed).
  The state-graph epic (design `docs/design/state-graph.md`, epic #239) began
  with the **`state.` entity domain** (issue #240): a new registry kind whose
  payload is a `StateDocument` (`lib/domain/state_machine/store/`) — canvas
  position, the **ordered outbound transitions** (`StateTransitionSpec`:
  target address · `StateTrigger` data (sealed manual / code / timed-on-domain
  / variable — behaviour lands with #244) · optional label), the explicitly
  captured per-category `StateSlices` (`lib/domain/state_machine/slices/` —
  clips + loop flags, mix volume/mute per bus, string variable values,
  per-domain tempos; `null` = uncaptured ≠ captured-empty; capture-from-live
  is #242), and an optional on-enter `code.` ref. `StateDocument` is a
  `ReferenceSource` (targets, trigger/tempo domains, slice clips/buses,
  on-enter script), stored map-native (`StateDocumentCodec`, schema v1, in
  `defaultEntityCodecs`) with references declared — so delete-impact on a
  state lists its inbound transitions and rename-refactor remaps them.
  Which state is *live* never persists (§8 decision 2 — firing is
  performance, not authorship). A fresh project seeds `state.intro` (one
  manual transition) → `state.verse` at the canvas positions the surface has
  always used; the registry-backed controller/canvas landed with #241.
  `StateMatchCondition` **migrated** from the old canvas-local id to the
  entity address (no compat shim): `GraphEvalContext.activeState` is an
  `EntityAddress` mirrored from the state machine's `activeStateAddress`
  (real registry addresses since #241), the guard picker authors addresses,
  `EdgeConditionCodec`
  persists the dotted address, and the graph exposes `guardStateAddresses` +
  `repointGuardState` — the guard-rename machinery #241 drives on every
  state rename. The
  `ClipRegistryPublisher` also listens to the domain graph and re-declares
  `ClipDocument.guardStateReferences` on every publish, so delete-impact on a
  state lists the clips whose MIDI-graph guards branch on it. Covered by
  domain unit tests (trigger/spec/slices/document round-trip identity, codec,
  registry seed + delete-impact + rename-refactor, guard repoint), publisher
  reference-sync tests, and an end-to-end `state_entities` integration test
  (seed → delete-impact → save → second launch restores the payloads
  identically).
  Issue #242 makes the slices **capturable from the live performance**.
  Capture is per category and explicit (design §4 — never a whole-world
  snapshot): `StateMachineController.captureSlice(address, category)` reads a
  `StateSliceSource` seam (`lib/engine/state/state_slice_source.dart`) and
  writes the state's payload as one journaled command — capturing is
  authorship (it dirties, saves, undoes), while *applying* a state stays
  journal-free (#243). The production source (`EngineStateSliceSource`,
  wired in `PhiEngine.start` through closures so a project swap needs no
  rewiring) reads each category off its owning controller: **clips** from
  `EngineMidiController.playingClipEntries` (the playing sessions with clip
  addresses + live loop flags; the boot session contributes nothing),
  **mix** off the materialised `mixTree` (strips *and* group buses with
  their live volume/mute; master is implicit and returns sit outside the
  tree, so neither captures), **variables** from the
  `RuntimeVariableRegistry`'s current values, and **tempos** from the bound
  registry's top-level `domain.` entities (authored tempo — a transient
  fader bend is performance, not the domain's tempo). A live-empty category
  captures as empty — meaningfully distinct from uncaptured. Editing rides
  the same journaled path: `clearSlice` un-captures a category, and the
  per-entry `remove…SliceEntry` methods (backed by pure
  `StateSlices.without…` helpers) trim one clip/bus/variable/tempo without
  recapturing — removing the last entry keeps the category
  captured-but-empty. Captured entries are entity addresses declared as
  payload references, so rename-refactor rewrites them and delete-impact on
  a clip/bus/domain lists the states that captured it; a *deleted* referent
  degrades gracefully at apply time through `StateSliceResolution`
  (`lib/domain/state_machine/slices/`) /
  `StateMachineController.resolveSlicesOf` — the surviving entries stay
  applicable and the missing addresses are surfaced for #243's notice.
  Covered by domain unit tests (category helpers, per-entry editing,
  resolution), controller capture tests against a fake source (capture
  reflects the source exactly, recapture replaces, clear/remove journal +
  undo, references follow a rename), an `EngineStateSliceSource` +
  `playingClipEntries` suite, and an end-to-end `state_slices` integration
  test (really-playing clip + live bus + variables + `domain.drum` captured
  exactly → per-entry trim → save → second launch restores the slices
  identically → deleting the captured bus resolves the rest and surfaces
  the missing address).
  Issue #243 makes entering a state **apply** what it captured — the
  journal-free application engine (design §4, §8 decision 2). A
  `StateApplicationEngine` (`lib/engine/state/state_application_engine.dart`)
  applies the entered state's resolved slices through a `StateSliceApplier`
  write seam (the mirror of `StateSliceSource`; production
  `EngineStateSliceApplier` over closures) in fixed order — **variables →
  tempos → mix → clips → on-enter script** (structure first, sound last,
  script over everything). Application is performance, not authorship: no
  payload writes, no journal entries — variables set through the
  `RuntimeVariableRegistry`, tempos as live per-domain overrides on the clock
  binding (`EngineMidiController.applyDomainTempo`, consulted by
  `ClipSession`'s base-tempo resolution and cleared on a project swap), mix
  levels live + engine-ramped (`PhiEngine.applyLiveBusLevel`, never
  persisted), and clips play/stop-to-match through the sessions (uncaptured
  leaves the playing set alone; captured-but-empty stops it). The entry
  itself comes from `StateMachineController.onStateEntered` — fired by
  `fire`/`setLive`, *not* by passive live re-seeding (load/rebind/delete
  fallback), so recovery lands on the authored state. The on-enter `code.`
  ref evaluates through the shell's shared `CodeEvaluator`
  (`PhiEngine.stateScriptEvaluator`, wired by the workstation). Every
  degradation — deleted referents, undefined variables, unstartable clips, a
  missing or failed script, even a throwing controller — becomes a
  `StateApplicationNotice` on `PhiEngine.lastStateNotice`, never a crash.
  Covered by application-engine unit tests (order, partial application,
  journal-free across applications, every degradation path), applier +
  tempo-override suites, controller entry-hook tests, and an end-to-end
  `state_apply_on_fire` integration test (capture → move the performance →
  save → fire from the canvas snaps variables/tempo/mix/clips back and runs
  the script while the project stays saved → deleting a captured bus
  surfaces the notice on the next fire).
  Issue #244 makes the stored `StateTrigger` data **behave** (design §5, §8
  decision 3). A `StateTriggerScheduler`
  (`lib/engine/state/state_trigger_scheduler.dart`, created in
  `PhiEngine.start`, exposed as `stateTriggers`) owns the three non-manual
  kinds: **timed** triggers arm on *entry* (the engine chains
  `onStateEntered` beside the application engine — a passively re-seeded
  live state starts no timers) with one reserved transport clock per
  schedule (`phi.state.timed.*`) paced from the domain's effective tempo
  (live override over the authored BPM) and checked by **querying the
  engine clock** each frame (the count-in precedent — no Dart timer in the
  timing path), cancelled when the source state is left early;
  **variable** triggers watch the `RuntimeVariableRegistry` and fire only
  on a change *onto* the match value (an already-matching value when the
  watcher arms never fires); **code** is `StateTriggerScheduler.fireTo`,
  adapted to the control plane's `StateControlPort` by
  `StateMachineControlPort` (v1: one machine, the qualifier is ignored) —
  kind-agnostic by design, the seam any trigger source can ride. Renames
  follow the refactor (`onStateMoved` remaps armed references in place, and
  the schedule sync is positional so a rename mid-count keeps the count); a
  fired transition whose target was deleted no-ops with a notice on
  `lastStateNotice`; `bindProject` cancels the old performance's schedules.
  Arming stays meaningful for **manual** transitions only:
  `StateMachineController.toggleArmed` refuses non-manual arms, and the
  journaled `setTrigger` drops the arm when a trigger leaves manual. On the
  canvas each transition wears a `StateTransitionBadge` at its curve
  midpoint naming the kind — the badge is the tap target (tap-to-arm moved
  to the badge for manual; the trigger editor for the rest) and tapping the
  curve opens the `StateTriggerEditor` dialog (kind + beats/domain from the
  project's `domain.` entities + variable/value from the runtime registry)
  for any kind. Covered by scheduler unit tests (fake-clock timed fire,
  cancellation on early exit, re-pace mid-count, rename-keeps-the-count,
  variable-match on change, fireTo resolution, every degradation), control
  port + controller trigger suites, badge/editor widget tests, and an
  end-to-end `state_triggers` integration test (badge → arm on the badge →
  editor authors timed (clock armed on the entered live state) → variable
  (schedule cancels; the variable change fires the transition) → fireTo).
  Issue #245 replaces the inspector placeholders with the **real SLICES /
  ON ENTER / TRANSITIONS panels** (design §6): `StateInspectorPanel`
  (`lib/shell/right_inspector/state_inspector_panel.dart`, rendered by
  `RightInspector` for a `StateEntitySelection`; the shared empty panel is
  `NoSelectionPanel`). **SLICES** shows the four categories with per-category
  capture / clear and the captured entries listed with per-entry `×` remove
  — an uncaptured category reads *not captured*, meaningfully distinct from
  *captured · empty*; capture is disabled without a wired `StateSliceSource`.
  **ON ENTER** is a `PhiSelect` over the project's `code.` tree (or none; a
  stored script no longer in the project stays offered as `… · missing`)
  driving the controller's journaled `setOnEnter`. **TRANSITIONS** lists the
  outbound specs — target, a tappable trigger summary (kind + params) that
  opens the shared `StateTriggerEditor` (its domain options now come from
  the static `StateTriggerEditor.domainOptionsOf`; the variable picker reads
  the selection's registry), and an inline-editable label through the
  journaled `setTransitionLabel` — with per-row remove (`disconnect`) and an
  add picker offering only unconnected non-self targets (`connect`), so
  transitions are authored here as well as on the canvas and both sides stay
  consistent (same controller, same journaled commands). Covered by
  controller tests (`setOnEnter` / `setTransitionLabel` journal one command,
  no-op on stored values, declare the on-enter reference), panel widget
  tests (every panel interaction mutating the payload through commands,
  not-captured vs captured-empty, canvas ↔ inspector consistency), and an
  end-to-end `state_inspector` integration test (capture / trim / clear on
  the live engine, on-enter to the seeded `code.scratch`, trigger + label
  edits re-badging the canvas, canvas-authored state offered by the add
  picker, inspector-side remove dropping the canvas badge).
  Issue #246 completes the epic with the **end-to-end + live-code wiring**.
  `state.` rows already ride the registry mirror like every kind (the boot
  full sync carries the seeded `intro`/`verse`); the `phi` library's `fire`
  verb gains the entity form — `state.verse.fire()` publishes the root
  `phi.ctl.state.fire` carrying the entity's own path as the target (v1: one
  machine; `state.fire('verse')` and the named-machine form are unchanged) —
  and the state root gains a **`state.current` readable** (the live state's
  path, `None` until pushed; reserved on the root, listed by `dir(state)`).
  The host side of that readable is a `StateCurrentMirror`
  (`lib/engine/bridge/`): `PhiEngine` pushes
  `phi._sync_state_current(...)` scripts through the shared
  `stateScriptEvaluator` (de-duped, fire-and-forget, the `RealRegistryMirror`
  pattern) on every live-state change — entries, passive re-seeds, renames —
  seeded at boot beside the mirror resync (memo reset across a stop → start
  re-init) and, because the controller notifies before it publishes an entry,
  queued **ahead of** the entered state's on-enter script, so the script
  already reads the new value; wiring the evaluator late seeds it
  immediately. Fire-from-code dispatches through #233's control plane —
  `phi.ctl.state.fire` → `ControlPlaneDispatcher` →
  `StateMachineControlPort` → `StateTriggerScheduler.fireTo` → the normal
  fire path — with the production dispatcher construction deferred to #334
  (blocked on the engine host bus tap, the #314/#316 pattern). Completion
  fixtures cover the `state.` namespace (the seeded states, the method
  table's `fire`). Covered by the python suite (entity / grouped /
  renamed-proxy fire forms, root-fire and non-state errors, `state.current`
  sync + reset + `dir`), `StateCurrentMirror` unit tests, a
  `state_current_wiring` engine suite (boot seed, entry/rename re-push,
  push-before-on-enter-script ordering, re-init re-seed), and the end-to-end
  `state_end_to_end` integration test — a two-state performance walking
  capture → fire-from-code on the exact frame `state.verse.fire()` emits
  (mix + variable slices apply, the journal stays empty, `state.current`
  reaches the evaluator, a `state.verse`-guarded MIDI-graph branch re-routes
  the preview exactly as a manual fire) → the timed follow-on armed on entry
  and cancelled on early manual exit → a variable-match transition re-firing
  and re-routing the guarded branch, with the LIVE capsule following.
- Time-domains layer seed (issue #60): pure-Dart `TimeDomain` (a named
  BPM tempo reference) and an immutable, copy-on-write `TimeDomainRegistry`
  (name→domain lookup) in `lib/domain/time_domains/`. The minimal object a
  clip subscribes to — the resolution surface the `DomainSubscriptionTransform`
  binds to (issue #61, wired into the demo chain). Since issue #102 a
  subscription is a **clock binding**: the transform is the identity on the note
  stream and its `boundTempo` sets the transport clock's rate — the first step
  of the inversion in [timing-architecture.md](timing-architecture.md) §4.
  Issue #104 adds the **Dart-side tempo-source seam** ([timing-architecture.md]
  (timing-architecture.md) §3): tempo is *played, not set*, so a played domain's
  tempo is a base rate (the subscription or session tempo) bent by a
  `TempoSourceStack` — a list of `TempoSource`s summed at control rate in Dart,
  never crossing the FFI boundary. Zero idle cost: with every source at rest the
  stack is the identity (no offset, no ticker, no FFI). The first and only source
  today is `FaderTempoSource` — a bipolar hand fader (`position` in `[-1, 1]`,
  `offset = position * bendRange`) riding the played domain's tempo, the "first
  gesture" that lets two time streams be bent against each other by hand.
  `EngineMidiController` owns the stack + fader (`tempoSources` / `tempoFader`),
  folds them into its `_effectiveTempo`, and re-ramps the transport clock live on
  a bend — and because tempo lives in the clock, bending it never re-pushes a
  note (the same clock-not-data property as the subscription). Future sources
  (state-machine ramps, LFO-on-time, spatial coupling, a convergence autopilot)
  compose behind the same seam without touching the engine. Still no tempo chrome
  (the fader is code-drivable, like the scatter / grab / effect-volume performer
  actions, until it graduates into the toolbar with the wider time-domain UI) and
  no independent per-domain engine clock (one shared default clock); domains as
  rampable, *playable* beat-accumulator clocks in the engine remain ahead.
- Project model & registry (design `docs/design/project-registry.md`) — the
  Phase-2 foundation for named, serialisable entities. Registry core (issue
  #118) in `lib/domain/project/`: an `EntityAddress` value type (dotted
  `kind.group….name`, valid by construction through the shared `NameValidator`),
  `RegistryEntity` / `RegistryGroup` nodes, and a kind-generic `ProjectRegistry`
  (ChangeNotifier) tree with transactional create / move / remove. Issue #119
  adds the command + undo layer (design §6): a self-contained `ProjectCommand`
  (`label` · `entitiesTouched` · `apply` / `revert` · `toJson`; the target —
  registry or clip — is bound at construction, so `apply`/`revert` take no arg)
  with concrete create-entity / remove-entity / move / create-group registry
  commands; a per-surface `UndoScope` (an undo *applies the inverse command*,
  recorded like any other) and an `UndoScopes` router so **undo follows focus** —
  Ctrl+Z/Y route to the active surface's stack, wired at the shell over a
  `CallbackShortcuts` that focuses the scope of the selected surface. The
  existing `ClipEditor` stack folds into this: its `ClipEditCommand`s now
  implement `ProjectCommand` and its stack *is* an `UndoScope` (exposed as
  `ClipEditor.undoScope`), making the MIDI surface the first registered scope;
  the piano roll no longer handles Ctrl+Z itself, letting the combo bubble to
  the shell. Gesture coalescing stays a convention (a drag mutates transient
  state and commits one command on release). `entitiesTouched` is the seam
  save/autosave dirty-tracking (#121) and the recovery journal (#122) will
  consume. Issue #120 adds references and refactoring (design §4): each entity
  declares its outgoing references (from its payload when that is a
  `ReferenceSource`, else an explicit set at `createEntity`), and the registry
  keeps a `BackReferenceIndex` (who points at whom) current on every mutation.
  That index makes **rename = refactor** — `move`/rename rewrites every referent
  (external *and* between moved siblings, payload included via
  `withReferenceUpdated`) as one undoable `MoveEntityCommand`, returning the
  dirtied referents for `entitiesTouched` — and powers **delete warnings**:
  `impactOfRemoving` returns a `DeleteImpact` listing the external entities a
  delete would strand. The `ReferenceSource` hook is structural today but does
  not preclude the deferred textual refactor of `code.` sources (live-coding
  epic). Issue #121 adds the persistence seam (design §5, §8) in
  `lib/domain/project/store/`: a project is a `.phi` folder whose `project.json`
  is a `ProjectManifest` (format version + name + tempo + scene name + master
  volume/mute + the journal-free workspace `layout`, issues #166/#253) and whose
  every entity is one pretty-printed JSON file (`kind` · `version` · `name` ·
  `references` · `payload`) at a path that mirrors its address — folders are
  groups, with an optional `_group.json` per group (display order + cosmetic
  colour, `GroupMetadata`) and a reserved `assets/` folder. A `ProjectStore`
  interface has the same Real/Fake split as `YseGateway`: `RealProjectStore`
  (`dart:io`) reads/writes the folder, an in-memory `FakeProjectStore`
  (`test/domain/project/test_doubles/`) backs the same bytes onto a map, and both
  delegate every byte of format logic to a pure `ProjectSerializer` (snapshot ↔
  flat path→contents map). Save writes **dirty entities only** (the command
  layer's `entitiesTouched` — a removed address deletes its file, or a removed
  group its whole subtree; a full save mirrors the registry by pruning stale
  files); a load rebuilds a fresh registry (references and their back-index
  restored) in each group's authored order. Opaque payloads (de)serialise through
  a per-kind `EntityPayloadCodec` — the `version` field is the migration seam —
  defaulting to a `JsonPassthroughCodec` until kinds carry real payloads (the v1
  migration epic). No lifecycle UI yet (later epic issue); the seam is
  domain-only and exercised by unit + real-filesystem round-trip tests.
  Issue #122 adds the command journal + crash recovery (design §7). A new
  `JournalStore` I/O seam (`lib/domain/project/store/`, `RealJournalStore` over
  `dart:io` + in-memory fake) owns the project's `.recovery/` corner:
  `journal.jsonl` (one JSON line per applied command, **fsynced per command** —
  review decision 4) and the `recovering` sentinel. Over it,
  `lib/domain/project/recovery/` holds the domain logic: `CommandJournal`
  (records a command's `toJson` as one line, `truncate` on save, sentinel
  passthrough), a `RegistryCommandCodec` that reconstructs each of the four
  registry commands from its journaled JSON (forward-only — replay never calls
  `revert`), and `CrashRecovery`, which on launch `detect`s a dirty journal
  (returning a `RecoveryOffer` with the unsaved count + a crash-loop flag when
  the sentinel is still set) and `recover`s by **domain-only replay**: load the
  last clean save → re-apply the journal onto the pure-Dart registry → hand back
  the snapshot for the engine to boot once, exactly as a normal load. The three
  options are `RecoveryChoice.replayAll` / `replayToPrevious` (walk back over a
  poison edit) / `skipJournal`; `recover` marks the sentinel for the duration so
  a crash mid-replay is caught next launch, and `resolve` truncates the journal +
  clears the sentinel after a clean re-save. The launch prompt is a
  `RecoveryDialog` (`lib/shell/recovery/` — shell, not the domain-agnostic design
  layer, since it reads a domain `RecoveryOffer`). Journaling of undo/redo (the
  inverse recorded as its own forward line) and the actual launch wiring land
  with the project-lifecycle UI (#123); this seam is domain-only and exercised by
  unit + real-filesystem recovery round-trip tests (the epic's persistence-leg
  "Done when") + a `RecoveryDialog` widget test.
  Issue #123 wires all of the above into a running lifecycle (design §9). A
  pure-Dart `ProjectController` (`lib/domain/project/lifecycle/`, ChangeNotifier)
  ties the registry, a location-bound `ProjectStore` + `CommandJournal` (built
  lazily through injected factories, so the controller itself touches no
  filesystem), `SessionState` (tempo + scene name live in the manifest),
  `CrashRecovery`, and an `AppSettings` store together — exposing New / Open /
  Save / Save-As-Duplicate / Rename, a `ValueNotifier<bool> isDirty`, a
  recent-projects list, and an autosave timer (default 60 s, cadence in settings,
  which keeps running while the transport plays). `AppSettings` (a `version` field,
  recent projects, pinned projects, autosave cadence, plus `AudioSettings` and
  `MidiSettings` value sections) persists to `%APPDATA%/phi/settings.json` through
  a Real/Fake `AppSettingsStore` seam (`lib/domain/project/app_settings/`); each
  section parses tolerantly (missing/malformed keys fall back to defaults) so an
  older file still loads, and pinned projects are listed first in the File menu and
  never dropped by the recents cap. A
  `ProjectDirectoryPicker` seam (real `file_selector` folder dialogs, faked in
  tests) fronts the Open/Save-location pick. Open replays a dirty journal through
  `CrashRecovery` behind the existing `RecoveryDialog`, then re-saves + resolves;
  save/autosave write the manifest (always) plus the dirty entities and truncate
  the journal; a Save-As names the project after the chosen `<name>.phi` folder.
  The shell adds the toolbar `ProjectMenu` + `DirtyIndicator`, a Ctrl+S save
  shortcut, and confirm-on-close via an `AppLifecycleListener` → widget-free
  `CloseGuard` (save / discard / keep-working) — all in `lib/shell/project/`,
  shared through a `ProjectActions` orchestrator. Production restores the
  most-recent project (and its recovery prompt) on launch via
  `Workstation.autoStartProject`; `PhiApp` owns the real controller + picker and
  passes an injected pair in tests. Dirty tracking is driven today by
  manifest-level changes (scene name, tempo — both persisted); registry-command
  journaling of undo/redo and clip-edit dirty tracking wait on the entity
  migration (#124), when the registry actually carries the clip/mix/domain
  entities, and hook into `ProjectController.recordCommand`. Covered by unit
  (controller + `AppSettings` + real-FS settings round-trip), widget (menu, dirty
  indicator, close guard), and an end-to-end `project_lifecycle` integration test
  (menu save clears the dirty dot; a dirty journal offers recovery on launch).
  Issue #124 migrates the app's existing singletons into the registry as the v1
  entity kinds (design §2, §8, review decision §12.1). Each migrated kind gets a
  typed payload + versioned `EntityPayloadCodec` wired onto every `ProjectStore`
  through `defaultEntityCodecs()`: `mix.` strips carry a `MixStrip`
  (`lib/domain/mix/`, a JSON-map payload — a strip is minted through the ordinary
  registry command layer, whose journal lines must be JSON), `clip.` carries the
  source `MidiClip` (`MidiClipCodec` — notes + meter; the transform chain/graph is
  a deferred serialisation surface), and `domain.` carries a `TimeDomain`
  (`TimeDomainCodec`). A fresh project is populated by `seedDefaultProject`
  (`lib/domain/project/registry_seed.dart`) — the demo clip (`clip.phrase_a`) and
  the demo time domains (`domain.drum`) created directly (initial state, not
  journaled); display names are slugged into valid addresses by `NameSlug`
  (`lib/domain/project/name_slug.dart`). **`PhiEngine` now consumes the registry
  as the channel source of truth (design §8, "channels first"):** it holds a
  bindable `mixRegistry`, materialises one `MixerChannel` per `mix.` entity
  (keyed by address so identity + live volume/peak survive a re-sync), and routes
  `addChannel`/`removeChannel` through `CreateEntityCommand`/`RemoveEntityCommand`
  recorded via `ProjectController.recordCommand` (dirty-tracking + journal). A
  bare engine (Phase-1 tests, no controller) owns a private empty registry so it
  still adds channels — they just live nowhere persisted. `Workstation` binds the
  engine to the controller's registry and rebinds when New/Open swaps it; the
  controller gained an injected `seedRegistry` hook. Live volume/mute/solo were
  left as engine-side performance state at the migration; issue #136 persists them
  (see below). Covered by unit tests (payloads, codecs,
  `NameSlug`, seed, registry-backed engine channels, store round-trip) plus an
  end-to-end `registry_migration` integration test (add a channel through the Mix
  surface → save → a second launch restores the channel, clip and domain).
  Issue #125 adds the **`RegistryMirror` seam** (design §8), the engine-bridge
  counterpart that will later mirror registry state into the engine's embedded
  Python namespace for the live-coding epic. Two halves: the domain
  `ProjectRegistry` now emits a fine-grained `Stream<RegistryEvent>` alongside its
  `ChangeNotifier` bump — one `RegistryEntityCreated` / `RegistryEntityMoved` /
  `RegistryEntityDeleted` per structural mutation (`setReferences` emits none;
  edges are not namespace) — and `lib/engine/bridge/` gains the `RegistryMirror`
  interface (`onCreate` / `onRename` / `onRegroup` / `onDelete`) with its
  production `NoOpRegistryMirror` and a `RegistryMirrorBinder` that forwards the
  event stream onto it, classifying a move into a rename (same parent group) or a
  regroup (new parent). `PhiEngine` owns the binder and rebinds it alongside its
  channel registry on every `bindProject`, so the no-op mirror is live in the
  running app. **No user-visible behaviour yet** — the seam exists so the
  live-coding epic plugs a real mirror in without re-plumbing the registry.
  Covered by unit tests (registry event emission, binder forwarding + move
  classification, no-op) plus an engine-level wiring test (channel add/remove and
  a project swap reach the injected mirror).
  Issue #135 finishes the `clip.` migration #124 bounded: a clip's
  **interpretation** now persists alongside its source notes. `lib/domain/midi/store/`
  adds the serialisation surface — a polymorphic `MidiTransformCodec` (a `type`-
  tagged, frozen wire contract over all ~20 transforms; `domain.` subscriptions
  persist by name and re-resolve live, `custom` transforms persist by definition
  name and re-link against the `CustomTransformRegistry`, falling back to a
  passthrough stub), an `EdgeConditionCodec` (always / state-match / runtime-
  variable) and a `MidiTransformGraphCodec` (nodes + guarded edges, ids remapped
  on load), all bundled by a `ClipDocument` (source + `MidiClipMode` + chain +
  optional graph). `MidiClipCodec` jumps to **schema v2** carrying that document
  and migrates a v1 payload (a bare clip) forward; the seed and the store now
  round-trip the whole document. Clip-edit **dirty tracking** (deferred from #123)
  lands too: `ProjectRegistry.updateEntityPayload` + an `UpdateEntityPayloadCommand`
  (journalable, replayed by `RegistryCommandCodec`) let a new engine-side
  `ClipRegistryPublisher` (`lib/engine/state/`) watch the live chain / editor /
  graph and publish each edit into the `clip.` entity through
  `ProjectController.recordCommand` (de-duped by JSON so selection/layout noise
  never dirties), so an edited-then-saved project persists the edits, not the seed.
  Covered by unit round-trip tests (every transform, the
  graph, the document + v1 migration, the registry method + command + journal
  replay), an engine-level publisher test, and an end-to-end `clip_persistence`
  integration test (edit a note + toggle a chip → save → reload restores both).
  Issue #139 closes the loop #135 left open: on **project open** the engine now
  **adopts** the loaded `clip.` document into its *live* session, so reopening a
  saved project runs the edited clip rather than the boot `defaultDemoChain()`.
  On every `PhiEngine.bindProject` the engine decodes the bound registry's first
  `clip.` payload into a `ClipDocument` and hands it to a new
  `EngineMidiController.adoptDocument`, which mutates the shared live objects **in
  place** — `chain.source.replaceWith` + `chain.setTransforms`, `ClipEditor.reset`,
  and a re-seed of the `MidiGraphController` from the document's graph + mode (a
  new `MidiGraphController.loadFromGraph` copies a branched graph over the live
  source, best-effort laid out by topological depth since positions aren't
  persisted) — so every surface already listening follows without re-wiring. The
  decode re-resolves `DomainSubscriptionTransform` names against the project's
  `domain.` entities and re-links `CustomTransform`s against the
  `CustomTransformRegistry`, both through a `MidiTransformCodec` that gained an
  optional `timeDomains` param (symmetric with its existing `customRegistry`); the
  shell threads its registry through `bindProject`. The `ClipRegistryPublisher` is
  detached during adoption and re-bound after, so replaying the loaded clip never
  dirties the project (it re-seeds its de-dupe baseline from the adopted state).
  Covered by unit tests (codec re-resolution, `loadFromGraph`, `adoptDocument`
  chain + graph modes), an engine-level `bindProject`-adopts test (incl. domain
  re-resolution and the no-spurious-publish contract), and an end-to-end
  `clip_adopt_on_open` integration test (edit → save → reopen restores the edit
  into `engine.midi.chain`, not just the registry payload).
  Issue #186 refactors `EngineMidiController` from *the clip* into a **session
  manager** (design `docs/design/midi-clips.md` §4), the structural heart of the
  MIDI-clips epic — deliberately behaviour-neutral. A new `ClipSession`
  (`lib/engine/state/`) bundles everything the controller used to hold globally
  **per clip**: the source clip + linear pipeline (`MidiTransformChain`), the
  piano-roll edits (`ClipEditor`), the branching interpretation
  (`MidiGraphController`), the engine `MidiTransport`, and the push-on-change
  memoisation — keyed by `EntityAddress` and borrowing the engine's shared pieces
  through a `ClipSessionHost` seam. The controller now owns only the genuinely
  **shared** singletons (the MIDI output gateway, the 3D `SceneField` + agent sink,
  the global `TempoSourceStack`/hand fader, and the live `GraphEvalContext` from
  the state machine + runtime variables), keeps a `_sessions` map with one
  **edited** session (the surface binds to it exactly as it bound to the single
  controller before), and drives the one frame ticker across sessions. Its whole
  pre-refactor surface (`chain`/`editor`/`graphController`/`playhead`/`play`/
  `stop`/`bpm`/`microtonal`/`tempoFader`/`adoptDocument` + the scene actions) now
  delegates to the edited session, so every caller and the full existing test
  suite are unchanged; `adoptDocument` still swaps the edited session's clip **in
  place** (surface bindings survive), while a new `openSession(address, document)`
  seam swaps the edited session outright — the library-selection hook the panel UI
  will drive. Covered by a `ClipSession`-in-isolation unit test (a stub host proves
  the bundle plays decoupled from the manager), a session-manager test
  (`openSession` swaps/reuses the edited session, a graph-mode document restores,
  and swapping leaks neither the transport nor the previous session), plus the
  controller suite and the MIDI/scene/clip integration suite.
  Issue #187 turns that seam into **concurrent playback** (design
  `docs/design/midi-clips.md` §4). Any number of sessions now play at once, each
  minting its transport on its **own** domain clock (`ClipSession.clockName`,
  derived per address) so two phrases run in different time domains against each
  other. The manager grows `playSession`/`pauseSession`/`resumeSession`/
  `stopSession` (keyed by address), group `playGroup`/`stopGroup` (act on every
  open session beneath a `clip.` group), and `stopAll` (the panel header); the
  edited-session `play`/`stop` gain `pause`/`resume`/`loop`. **Pause** freezes the
  bound clock (tempo 0 — a tempo-0 clock holds its beat, verified in dart-yse's
  `clock_clip_test`) and `allNotesOff`s, so **resume** continues mid-loop without
  depending on the clip transport re-anchoring across a stop/play; **stop**
  rewinds. The **loop** flag (#184) is finally wired into playback — loop off
  pushes `loopBeats <= 0` (one-shot); toggling it live re-pushes only the loop
  length. **Scene keys are namespaced** per session (`ClipSession.sceneKeyBase`,
  a disjoint band the manager allocates) so concurrent clips spawn side by side in
  the one `SceneField` and a stopped clip clears **only its own** agents (the scene
  demo and other clips survive — the pre-#187 whole-field clear on stop is gone).
  Covered by concurrency + pause/resume + loop unit tests and a
  `midi_concurrent_playback` integration test driving two clips through the real
  shell.
  Issue #188 wires all of that domain + engine work into an actual **library
  panel** on the MIDI surface (design `docs/design/midi-clips.md` §3, §4) — a
  collapsible left sidebar (`lib/surfaces/midi/library/library_panel.dart`,
  default collapsed, mirroring the transform-chain sidebar) showing the `clip.`
  namespace as a tree: groups as folders, clips ordered within them (registry
  child order = the persisted `_group.json` order). A new engine-side
  `ClipLibraryController` (`lib/engine/state/`, a `ChangeNotifier`) is the panel's
  single seam over the `clip.` registry, the `EngineMidiController` session
  manager, and the `ClipLibrary` command factory: it flattens the tree into
  `ClipTreeNode`s, and every structural edit goes through the journaled command
  layer (create-entity via `ClipLibrary` for new/duplicate, `CreateGroupCommand`
  for groups, `MoveEntityCommand` for rename-refactor + drag-to-regroup,
  `ReorderChildCommand` for in-section reorder, `RemoveEntityCommand` for delete),
  applied + recorded through `ProjectController.recordCommand`. **Selection** opens
  the clip as the edited session (the roll/ghost/graph rebind to it — the surface
  keys the viewport by the edited address); the **context menu** offers new clip ·
  new group · duplicate · rename · delete (delete routing through the
  `DeleteImpactDialog` when the node is still referenced); **drag** re-parents a
  row into a group, out onto the body to un-group, or onto a sibling to reorder;
  **per-row play/loop toggles** + a playing dot, group rows play/stop their whole
  subtree, and the header carries **stop-all**. To let a row play a clip *other*
  than the one open in the editor, `EngineMidiController` gains `ensureSession`
  (open a session without making it edited); `openSession` is now that plus the
  edit-swap. The shell builds the controller when a project + MIDI subsystem are
  present and rebinds it on New/Open (registry swap). Covered by a
  `ClipLibraryController` unit test (tree/order, selection swap, every command,
  regroup/reorder reflected in the registry, per-row/group play state), a
  `library_panel` widget test (fake gateway — tree rendering, select, every
  context-menu path, drag-to-group, play/loop/stop-all), and an end-to-end
  `midi_library_panel` integration test (expand → add → select → play → stop-all
  through the real shell). **Deferred (follow-up #197):** the `ClipRegistryPublisher`
  still watches the boot session's objects, so edits made *after* a library
  selection don't yet persist — the publisher must follow the edited session.
  Issue #190 gives the piano-roll editor **length authority, auto-extend, a loop
  toggle, and a transport row** (design `docs/design/midi-clips.md` §5) — building
  on #189's parametrised header. A new `ClipTransportRow`
  (`lib/surfaces/midi/clip_transport_row.dart`) sits under the header with editable
  `bars × beats-per-bar` fields (the loop window is the clip's declared
  `totalBeats`, not the output's extent), an **auto-extend** toggle (default on),
  and — when a session is live — **play / pause / stop / loop** for the edited clip.
  `ClipEditor` gains `setLength` and `autoExtend`: entering or dragging a note past
  the end grows `bars` to fit (rounded up), journaled *with* the note edit as one
  `CompositeClipCommand` (`lib/domain/midi/edit/`, alongside the new
  `SetLengthCommand`) so a single undo restores both note and length; a velocity
  paint never re-grows. Shrinking below where notes live first warns
  (`ConfirmDialog`); the transport buttons drive the edited session through new
  `ClipLibraryController` methods (`playEdited` resumes from a pause, `pauseEdited`,
  `stopEdited`, `toggleEditedLoop`). The **loop flag now persists**: the
  `ClipRegistryPublisher` reads the live loop into its snapshot and exposes
  `republish()`, which `EngineMidiController.onEditedLoopChanged` fires on a toggle
  (fixing the prior `loop: true` overwrite). Covered by `ClipEditor` length +
  auto-extend unit tests (grow-on-entry, undo restores both, floors, velocity
  no-regrow), a `ClipTransportRow` widget test, a `midi_surface_transport` widget
  test (length applies, shrink warns/confirms/cancels, play/pause/stop against the
  fake transport), publisher loop/length persistence tests, and an end-to-end
  `midi_length_loop_transport` integration test (length field grows + persists,
  loop toggle flips + persists, header play/stop drive the transport).
  Issue #191 closes the MIDI-clip epic (design `docs/design/midi-clips.md` §5,
  §7 decision 3) with **caret step entry** and an **import/export flow polish**.
  The piano roll gains a `PianoRollCaret` (`lib/surfaces/midi/piano_roll_caret.dart`,
  a beat-position/lane edit cursor, pure view state): with the roll focused, an
  arrow key summons + moves it by one grid step, `Enter` drops a grid-length note
  at its lane/beat (through `ClipEditor.addNote`, so it undoes normally) and
  advances it, and `Escape` dismisses it — while a *selected* note still nudges
  with the arrows when no caret is up (`_arrow` routes caret vs. selection). The
  painter draws the caret as an insertion cursor (a guide at its beat + an outlined
  grid-length cell). **Import** no longer overwrites the open clip: the `MidiFileIo`
  seam now returns the picked *filename* alongside the bytes, and the surface routes
  a dropped / picked `.mid` through a new `ClipLibraryController.importFromSmf`,
  which lands it as a **new** clip entity in the selected group (the edited clip's
  group, or top level), slugged from the filename, and opens it — via the #185
  `ClipLibrary.importFromSmf` command, journaled like any create. **Export** is
  unchanged in spirit (the header writes the *selected* clip's transformed output,
  named from its leaf). A bare viewport with no library still falls back to the
  legacy in-place import. Covered by `piano_roll_caret` widget tests (summon /
  move / drop / advance at 1/8 + 1/16 grids, Escape dismisses, selection still
  nudges), a painter caret repaint test, a `ClipLibraryController` import test
  (new entity in the selected group + opened), and an end-to-end
  `midi_step_entry_import_export` integration test (caret authors a note, IMPORT
  lands a new entity, EXPORT round-trips the selected clip) — the old
  `midi_smf` integration test (which asserted the now-removed in-place overwrite)
  is superseded by it.
  Issue #198 gives the zoomed roll **independent panning** (follow-up to #189,
  which only moved the view by zooming). `PianoRollView` gains pan arithmetic —
  `maxScrollBeats` / `maxScrollLanes`, `withScrollBeats` / `withScrollLanes`, and
  `pannedBy` — all clamping through the *same* bounds zoom uses, so pan and zoom
  share one source of truth and the clip can never pull away from an edge. A new
  `PianoRollScrollbar` (`lib/surfaces/midi/piano_roll_scrollbar.dart`, unit-agnostic
  — beats for the horizontal bar, lanes for the vertical) overlays the roll's edges
  and hides itself while the axis fits; `PianoRollEditor` also pans on a
  **middle-mouse drag** (a `Listener` path that leaves the left button free for
  editing, active only once zoomed). Both feed the session-local view the
  `MidiViewport` owns, so the velocity lane — sharing that view — scrolls in
  lock-step for free. Covered by `PianoRollView` pan/clamp unit tests, a
  `piano_roll_pan` widget test (scrollbars appear only when zoomed; thumb + middle
  drags scroll the view) and an end-to-end `midi_pan` integration test (Ctrl+wheel
  zoom, then a middle-drag pans and the velocity lane follows). The header snap
  picker's dropped `SNAP` label (a narrow-width layout concern) is split out to
  #274.
  Issue #136 finishes the `mix.` migration #124 bounded: a channel's **live mix
  state** (user volume, mute, solo) now persists alongside its identity. `MixStrip`
  gains `volume`/`muted`/`soloed` and `MixStripCodec` jumps to **schema v2**,
  migrating a v1 (identity-only) payload forward with defaulted keys. The engine
  restores that state when it materialises a channel from a `mix.` entity
  (`applyVolume`/`applyMuted`/`applySoloed` before the solo-aware effective-volume
  sweep), and publishes live changes back through the same
  `UpdateEntityPayloadCommand` seam #135 built — **gesture-coalesced** (design §6):
  a fader drag brackets its transient per-tick mutations between
  `beginChannelVolumeGesture` / `endChannelVolumeGesture`, so the whole drag emits
  **one** journaled `mix.` payload command on release instead of one per tick,
  while discrete mute/solo toggles persist immediately (all de-duped by JSON so a
  no-op change never dirties). `ChannelStrip` gained `onVolumeChangeStart` /
  `onVolumeChangeEnd`, wired by the Mix surface to the engine's gesture boundary.
  Covered by unit tests (strip + codec incl. v1→v2 migration, store round-trip),
  engine tests (materialisation restores state; the coalescing contract — one
  command per drag, immediate for taps/toggles, de-dupe, master no-op), widget
  tests (the fader brackets its changes with start/end), and an end-to-end
  `mix_persistence` integration test (add a channel → mute + solo + drag its fader
  → save → reload restores volume/mute/solo).
  Issue #165 opens the mix epic (design `docs/design/mix.md` §3) with
  **kind-declared group payloads** — the registry seam that lets a `mix.` group
  *be a bus*. A `RegistryGroup` now carries an optional `payload` + `references`
  (the same shape an entity does, mutable in place since a group is a container),
  so a group bus has its own fader/sends. Which kinds' groups *persist* a payload
  is a store-level declaration (`defaultGroupPayloadKinds()` → `{mix}`); for a
  declared kind the group's `_group.json` gains a `kind`/`version`/`name`/
  `references`/`payload` envelope beside the existing order/colour metadata,
  encoded by the same per-kind `EntityPayloadCodec`, while an undeclared kind
  (`clip.`) is byte-for-byte unchanged. Group payloads join the ordinary command
  layer — `createGroup(payload:, references:)` (via `CreateGroupCommand`) and a
  new `UpdateGroupPayloadCommand`/`ProjectRegistry.updateGroupPayload`, both
  journalled and replayed by `RegistryCommandCodec` — and the **back-reference
  index** now indexes a group bus's own edges, so delete-impact warns when a
  return still has a group sending to it and rename-refactor rewrites a group
  bus's sends (a `ReferenceSource` payload via `withReferenceUpdated`, or its
  declared set). No surface wiring yet — a group bus is created only through the
  domain layer until the grouped rack lands (#169); `MixStrip` grows real `sends`
  in #166. Covered by domain unit tests (registry create/update/delete-impact/
  rename-refactor over group payloads, the two commands, journal replay) plus
  in-memory and real-filesystem store round-trips (`_group.json` payload
  envelope; `clip.` groups unchanged).
  Issue #166 grows the **mix domain** (design `docs/design/mix.md` §3–§4, §10):
  `MixStrip` gains `isReturn` (a top-level return bus) and an ordered `sends`
  list of the new `MixSend` value type (`{to, level, preFader}`, slot = index),
  and `MixStripCodec` jumps to **schema v3**. A strip is now a `ReferenceSource`:
  its `references` are its send targets, so a strip's sends feed the
  back-reference index and `withReferenceUpdated` rewrites a send's `to` when its
  return is renamed/moved (the same seam group buses already use). Send targets
  are validated at edit time — `SendTarget.isReturn`/`validate`
  (`lib/domain/mix/send_target.dart`) reject a send to anything but a top-level
  `mix.` return, so an illegal wiring never reaches the journal or the engine.
  **One-name re-alignment (§10 decision 1):** `MixStrip`'s free-form display name
  is **dropped outright** — no compat shim, a stored `name` key is simply no
  longer read. A channel is named by its **address leaf**: the engine names each
  `MixerChannel` from `address.name` (now `final`), so `renameChannel` collapses
  to a pure registry **move** (a same-slug rename is a no-op) and the surface
  header shows the slug (`lead synth` → `lead_synth`). Master state (volume, mute)
  moves into the **project manifest** (`ProjectManifest.masterVolume`/
  `masterMuted`) — master is not an entity, so its state persists there; wiring
  the live engine master into/out of the manifest lands with the engine work
  (#168). Covered by domain unit tests (strip/send/codec incl. v2→v3, the
  `ReferenceSource` rewrite, send-target validation, manifest master round-trip),
  engine tests (channels named from the address, rename-as-move, live-state
  persistence preserving sends), and the end-to-end `mix_rename_remove`
  integration test (a spaced rename now shows the slugged leaf and round-trips a
  save/reload).
  Issue #168 makes the engine **tree-aware** (design `docs/design/mix.md` §5, §8):
  `PhiEngine._syncChannelsFromRegistry` now walks the whole `mix.` tree instead of
  the flat top level — materialising a channel per node (a `mix.` group *is* a bus,
  created **before** its children so they have a parent; a top-level `return: true`
  entity is a `createReturnChannel` outside the tree with auto-upgraded send slots),
  re-parenting a moved node with `moveChannel` (a regroup keeps the same leaf name,
  so the engine correlates the gone/appeared addresses and preserves the gateway
  channel + its live meters rather than tearing it down), destroying removed nodes,
  and — in a **second pass**, once every channel exists — wiring aux sends to their
  return buses (`setSend`/`setSendLevel`/`clearSend`, reconciled against what is
  already applied). Tree **mute/solo** collapse to effective gateway volumes
  (`_recomputeEffectiveVolumes`): mute wins on the path (a soloed leaf inside a
  muted group stays silent), solo keeps the soloed nodes ∪ their descendants ∪ their
  ancestors audible, and **returns are exempt from solo** (§10 decision 3). The
  engine exposes a returns list (`PhiEngine.returns`) and a send-edit API
  (`setChannelSend`/`clearChannelSend`/`setChannelSendLevel` with
  `begin`/`endSendLevelGesture` coalescing, the same one-command-per-drag pattern as
  the fader) for the surface work (#170). **Master** volume/mute — not a registry
  entity, so manifest state (design §3) — now round-trips: `SessionState` grows
  `masterVolume`/`masterMuted` (the manifest's in-memory carrier, like tempo), the
  `ProjectController` folds them into / out of the manifest on save/open (a master
  change dirties the project), the shell mirrors them onto the engine, and
  `PhiEngine.setMasterMuted` collapses the effective master volume to zero while
  remembering the user value. The right inspector's master fader now binds to the
  session. Covered by engine unit tests (`engine_mix_tree_test` — group create/move/
  remove reconciliation, second-pass send wiring incl. sender-before-target,
  the full solo/mute truth table, returns, send-edit + gesture coalescing; plus
  master-mute effective volume in `engine_test`), controller tests (master
  volume/mute manifest round-trip + dirty-on-change), and an end-to-end
  `mix_master_persistence` integration test (drag the master fader → save → reload
  restores it).
  Issue #169 turns the flat Mix rack into the **grouped rack** (design
  `docs/design/mix.md` §7). `PhiEngine` gains a tree view — `mixTree`, a
  `MixTreeNode` forest (`lib/engine/state/`) rebuilt on every re-sync, nesting each
  non-return channel under its parent — plus the surface-facing tree-editing façade:
  `addGroup` (a `mix.` group bus via `CreateGroupCommand`), `addReturn` (a top-level
  `return: true` entity), `moveChannelToGroup` (drag-into / drag-out re-parenting via
  `MoveEntityCommand`), and `moveChannelBefore` (in-section reorder). Reorder lands as
  a new registry primitive: `RegistryGroup.reorder` + `ProjectRegistry.reorderChild`
  (order-only, no address/reference change, so no lifecycle event) and a journalled
  `ReorderChildCommand` (decoded by `RegistryCommandCodec`); the `ProjectController`
  now derives each group's `_group.json` child `order` from the **live registry** on
  save, so a reorder persists (top-level order stays alphabetical, as before). Group
  buses also finally persist their own fader/mute/solo — `_persistChannelState` writes
  through `updateGroupPayload` for a group node. The surface (`mix_surface.dart`)
  renders top-level strips + framed group sections (a group's own header strip beside
  its child strips), a `+` add-menu (`showMenu`: add channel · group · return), and a
  `Draggable` header handle per leaf strip (added as an optional `dragHandle` slot on
  `ChannelStrip`); nested `DragTarget`s route a drop — onto a group section = re-parent
  in, onto a sibling = reorder / re-parent, onto the open rack = un-group. Covered by
  domain unit tests (`reorder_child_command` — registry reorder, command apply/revert,
  journal codec), engine tests (`engine_mix_surface_api` — addGroup/addReturn, drag
  re-parenting, reorder, `mixTree`, group-bus persist), widget tests (`mix_surface` —
  group rendering, the add-menu paths, drag-to-group + un-group + reorder driven by
  real drag gestures), and an end-to-end `mix_grouped_rack` integration test (add a
  group + channels → drag both in → reorder → save → reload restores the group with
  its children in the dragged order).
  Issue #170 adds the **returns section + per-strip sends UI** (design
  `docs/design/mix.md` §4, §7). The Mix rack pins a framed **returns section**
  beside master, one `_ReturnStrip` per `PhiEngine.returns` bus — fader, mute,
  meter, **no solo** (returns are exempt, §5, via a new `ChannelStrip.soloable`
  flag) and no drag handle. Every leaf strip and group-bus header gains a compact
  **SENDS** area under it: one row per aux send — a returns-only target picker
  (`PhiSelect<MixerChannel>`), a vertical-drag level **mini-fader**, a pre/post
  toggle, and a remove `×` — plus an add-send picker while a return exists to
  target (slots auto-upgrade, no cap). The surface reads/edits sends through two
  new engine getters (`channelSends`, `returnChannelFor`) over the #168 send-edit
  API (`setChannelSend` / `clearChannelSend` / `setChannelSendLevel` +
  `begin`/`endSendLevelGesture`): editing a target rewires the slot through the
  registry sync, removing clears it, and a level drag is **gesture-coalesced**
  (the mini-fader holds a transient value during the drag; the engine journals one
  payload command on release) — the same pattern as the fader. Covered by widget
  tests (`mix_surface` — add/edit/remove send, returns-only picker, pre/post
  toggle, one-command-per-drag coalescing, group-bus sends, returns render without
  a solo button) and an end-to-end `mix_sends_and_returns` integration test (wire
  a send → flip pre-fader → drag its level → save → reload restores target,
  pre/post and level, and the return re-renders in its section). Return delete via
  the delete-impact dialog stays with #171.
  Issue #171 completes the mix epic with **layout-aware master meters + return
  delete-impact** (design `docs/design/mix.md` §6, §7). The master strip now shows
  **one meter bar per speaker output** (`ChannelStrip.outputPeaks` → a row of
  vertical bars keyed by `ChannelStrip.outputMeterKey`): two on stereo, six on 5.1.
  `MixerChannel` gains telemetry-driven `outputPeaks` (`applyOutputPeaks` notifies
  on a count change *or* a perceptible level move), and the engine's telemetry tick
  reads the gateway's live `masterOutputCount` + `masterPeakOutput(i)` — so the bar
  count follows a device/layout swap **without a restart** (user strips keep their
  single meter). **Return delete-impact**: a return strip gains a remove `×` (keyed
  `MixSurface.returnRemoveKey`, distinct from the leaf strips' shared key) that runs
  `PhiEngine.channelRemovalImpact` → the strips / group buses still sending to it →
  and, when non-empty, raises a new string-based `DeleteImpactDialog`
  (`lib/design/widgets/dialog/`, beside `ConfirmDialog`) listing them; confirming
  calls `removeChannelClearingSenders`, which clears each sender's targeting send
  (journaled payload edits) before removing the return, so no dangling send is left.
  The senders are read straight off the live mix model rather than the registry's
  back-reference index: a `mix.` payload is stored map-native (the journal contract,
  design §3), so it is not a `ReferenceSource` and its sends never enter that index.
  Covered by widget tests (`mix_surface` — stereo/5.1 bar-count derivation from the
  fake gateway, user strips stay single-meter, delete-a-return warn → confirm →
  clear, cancel keeps, no-sender direct remove; `channel_strip` — bar rendering),
  engine tests (`engine_mix_surface_api` — impact lists strip + group-bus senders,
  clear-then-remove, per-output telemetry + live count change), and an end-to-end
  `mix_master_meters_and_return_delete` integration test (stereo → 5.1 without
  restart; wire a send → delete the return → dialog warns → confirm clears it).
- **Racks & voices domain foundation** (issue #204, epic #203, design
  `docs/design/racks-and-voices.md` §3–§5) — the pure-Dart entities the racks
  epic binds *note → sound → bus* on, three new registry kinds registered in
  `RegistryKinds` + `defaultEntityCodecs()`:
  - `voice.` — `VoiceDefinition` (`lib/domain/voice/`), the keystone: an
    `internal` voice points at a `synth.` definition + `mix.` bus, an `external`
    voice carries a MIDI channel + bus; colour is an opaque design-token string.
    It is a `ReferenceSource`, so `voice → synth` and `voice → mix` edges feed the
    back-reference index (delete-impact, rename-refactor). `ChannelAllocation`
    (same folder) is the immutable, copy-on-write 1–16 engine-channel table for
    internal voices — stable assignment, lowest-free reuse on delete, and a
    `ChannelExhaustedException` at the accepted v1 16-voice ceiling; it round-trips
    to JSON so allocations survive save/load.
  - `synth.` — `SynthDefinition` (`lib/domain/synth/`), an `abstract` recipe
    hierarchy dispatched on `SynthKind`: `SineSynth`, `VaSynth` (the full VA
    panel — oscillator stack, filter, amp/filter envelopes, LFO), `FmSynth`
    (bank-asset ref + patch index + optional algorithm/feedback/per-op
    overrides), `SamplerSynth` (SFZ asset *or* single-sample recipe). Definitions
    carry no engine identity — voices instantiate them.
  - `fx.` — `FxDefinition` (`lib/domain/fx/`), one effect instance = `FxKind` +
    a flat `name → value` param bag; placement lives in each `mix.` bus's ordered
    `inserts` list (`MixStrip` gained `inserts`, codec bumped to v4), so
    `mix.inserts → fx` edges also feed the index.
  - Every payload round-trips identity through its versioned codec; the
    `racks_round_trip_test` builds a synth/voice/fx/mix registry, saves & reloads
    through the store, and asserts both identity and the three delete-impact edges.
    Pure-domain issue (no user-visible surface) — covered by unit tests plus the
    serializer round-trip; UI + gateway materialisation land in later epic issues.
- **`MidiNote.channel` → `MidiNote.voice`** (issue #205, epic #203, design
  `docs/design/racks-and-voices.md` §6) — the note-flow half of the racks epic,
  no compat shim. A note now carries a `voice.` **address string** (`null` =
  unrouted → the seeded `voice.default`) instead of a bare channel int; the same
  migration threads through `DslNote`, `VoiceRoutingRule`/`SplitVoice` (voice
  refs), the transform codec, clip persistence + the edit journal, and the
  `NoteField` enum (the `channel` field dropped — a voice is an address, not a
  comparable scalar). `seedDefaultProject` now seeds `voice.default` →
  `synth.sine` → `mix.master`, and the default demo chain routes there.
  `VoiceChannelResolver` (`lib/domain/voice/`) is the pure voice-address → `0..15`
  transport-channel map (internal via `ChannelAllocation`, external via configured
  channel); at flatten time `ClipSession.pushEvents` resolves each voice through
  the `ClipSessionHost` seam and **degrades gracefully** — a note routed to an
  unknown voice plays nothing and is surfaced via `EngineMidiController.unresolvedVoices`
  rather than crashing. SMF `SmfReader`/`SmfWriter` map file channels ↔ voices
  (channel 1 ↔ `voice.default`, others ↔ `voice.channel_<n>`), so a
  voice → SMF → voice round-trip is lossless. Scene keying + voice colour fold a
  voice into a stable bucket via `voice_hash.dart`. Full engine/gateway voice
  materialisation is still a later epic issue.
- **Gateway synth surface** (issue #206, epic #203, design
  `docs/design/racks-and-voices.md` §3–§4) — the engine-bridge half that turns a
  `synth.` *definition* into a live engine voice pool, the same Real/Fake split as
  `YseGateway`/`MidiGateway`. `SynthGateway.materialiseSynth(definition, channel:)`
  (`lib/engine/bridge/`) mints a `MaterialisedSynth` handle; the handle re-applies
  an edited definition (`applyDefinition`), binds its output to a mix bus
  (`bindToBus` → `Sound.fromSynth`, re-pointing on a later call), and disposes the
  `Sound` before the `Synth` (the leak-safe order). Whether an edit re-applies
  **live** or **rebuilds** the pool is the pure, shared
  `SynthMaterialisation.needsRematerialise` rule (kind / voice-count change, an FM
  bank swap, a sampler instrument swap → rebuild; VA panel and FM patch/override
  edits → live). `RealMaterialisedSynth` wraps the confirmed yse calls per kind —
  `addSineVoices` (on the allocated channel) / `addVaVoices` + the `setVa*` panel /
  `addFmVoices` + `Dx7Bank.load` + `setFmPatch` + `setFm*` overrides /
  `addSamplerVoices` over `SfzInstrument.load`/`fromSample` — behind a
  `MixBusResolver` (bus id → `Channel`) and an `AssetPathResolver` (relative ref →
  absolute path) the engine wires in #208. The session transport grew a connection
  surface — `MidiTransport.connectSynth`/`disconnectSynth` (broadcast to an
  internal voice, channel-filtered) and `connectMidiOut`/`disconnectMidiOut` (the
  external port; the issue-#101 lazy play-connect now routes through it). Assets are
  copied project-portable via `AssetImporter` / `FileAssetImporter`
  (`lib/domain/project/store/`): an import copies a `.syx`/`.sfz`/sample into the
  `.phi` folder's `assets/` and returns a POSIX relative ref, reusing byte-identical
  files and uniquifying basename collisions. Engine-bridge seam with no user-visible
  surface (the racks UI is #209–#212), so covered by unit tests via the fakes
  (`FakeSynthGateway`, every kind + re-application + bus binding + disposal + the
  transport connections) plus the real-FS asset-importer round-trip — no integration
  test, exactly as the earlier bridge seams (`RegistryMirror`, the clip transport).
  VA/FM/sampler pools register omni until `dart-yse` grows a channel parameter on
  their `add*Voices` (filed upstream); sine already registers on its channel.
- **Gateway fx surface + parsed MIDI-in** (issue #207, epic #203, design
  `docs/design/racks-and-voices.md` §5, §7) — the engine-bridge fx half plus the
  input stream, same Real/Fake split. `FxGateway` (`lib/engine/bridge/`) has two
  primitives: `materialiseFx(definition)` mints a `MaterialisedFx` handle (one
  `DspObject`/`Compressor` per `FxKind`, its flat `params` map applied through
  click-free setters — a same-kind edit applies live, a kind change rebuilds), and
  `createChain(busChannelId:)` mints an `FxChain` that links a bus's `inserts`
  handles head-to-tail and places the head pre-fader via `Channel.dsp`.
  `FxChain.setInserts(ordered)` is build (first call) · reorder (new order) ·
  detach (empty list) in one, borrowing the handles (the owner disposes them).
  `RealMaterialisedFx` maps each kind to its factory + recognised param keys
  (`frequency`/`q`/`impact`/taps/`grain*`/compressor curve …); `patcherInsert` is
  **reserved** — it builds no object (`isPlaceable == false`) and a chain skips it
  until the patcher epic wires it. Reorder is cycle-safe **without** a wrapper
  unlink (the wrapper's `DspObject.link` can't clear a `next`; the native API can —
  filed **yvanvds/dart-yse#42**): `RealFxChain` keeps a permanent bypassed
  **terminator** `DspObject` as the tail, re-linking every real object to its
  successor (the next insert or the terminator) on each placement, so no stale edge
  survives and the walk always ends at the terminator. The **parsed MIDI-in stream**
  grows `MidiGateway` with `inputEvents` — a `Stream<MidiInputEvent>` (note on/off +
  velocity + 1-based channel + port) decoded from the bridge's `MidiInParsedMessage`
  by the pure, yse-free `MidiInputEvent.fromParsed` (velocity-0 note-on → note-off;
  non-note messages filtered); one `RealMidiGateway` subscription drives both the
  unchanged activity tick (design §6) and the new note stream (design §7). Nothing
  routes these events yet (arm/audition is #211) and the fx gateway has no UI
  consumer yet (#212), so — like #206 — this is a non-user-visible seam covered by
  unit tests via the fakes (`FakeFxGateway`'s chain build/reorder/detach faithfully
  simulates the terminator link-walk to prove reorder never cycles; `FakeMidiGateway`
  emit helpers) plus the pure `MidiInputEvent.fromParsed` decode; no integration test.
- **Engine voice/fx materialisation + session transport wiring** (issue #208,
  epic #203, design `docs/design/racks-and-voices.md` §3, §5, §6) — the engine
  layer that turns the #206/#207 gateway primitives into live sound, reconciled
  against the registry the way `mix.` channels are. A new `RackMaterialiser`
  (`lib/engine/state/`) runs at the tail of `PhiEngine._syncChannelsFromRegistry`
  (bus ids must exist first) and materialises, **keyed by address so live engine
  state survives a re-sync**: one engine synth + `Sound` per **internal `voice.`**
  (instantiated from the voice's `synth.` definition on the voice's allocated
  engine channel, bound to its `mix.` output bus — two voices sharing one
  definition each get their **own** synth, so a definition edit re-applies to
  every dependent voice; a `SynthMaterialisation.needsRematerialise` edit rebuilds
  a fresh handle while a live edit / bus re-point mutates in place; re-pointing a
  voice's synth swaps the sound behind its stable identity), and one linked
  `DspObject` chain per **`mix.` bus with `inserts`** (the ordered `fx.` instances
  materialised as handles, placed via the `FxChain`; reorder / remove / delete
  follows the registry). It owns an internal-voice `ChannelAllocation` and hands
  the fresh `VoiceChannelResolver` + voice→synth map to
  `EngineMidiController.bindVoices` on every re-sync. **Session transports connect
  by routed voice:** `ClipSession.pushEvents` now reconciles its transport's
  connections against the voices its clip routes to — `connectSynth` for every
  internal voice with a materialised synth (keyed by handle identity, so a
  re-materialised synth reconnects while a live-edited one stays), `connectMidiOut`
  when any routed voice is external, disconnecting on re-route and on stop /
  teardown (the `ClipSessionHost` seam grew `synthForVoice` / `isExternalVoice`).
  `RealMidiTransport.play` no longer force-connects MIDI-out (the #101 lazy
  connect) — the session drives it — so an internal-only clip no longer bleeds to
  the external port. Deferred-disposal ordering (retire handles only **after**
  `bindVoices` lets playing sessions disconnect them) keeps a live re-point
  leak-safe. An unknown / deleted voice in a playing clip still degrades
  gracefully (notes silent + surfaced via `unresolvedVoices`). `PhiEngine.production`
  wires `RealSynthGateway` / `RealFxGateway` with a `MixBusResolver` the real yse
  gateway builds over its live channels; the real asset-path seam waits on the
  racks import UI (#211). Non-user-visible engine-bridge seam (the racks UI is
  #209–#212, real audio needs the DLL), so — like #206/#207 — covered by unit
  tests via the fakes: an engine-level `engine_racks_test` (materialisation
  lifecycles, live-vs-rebuild re-application reaching all dependent voices, bus /
  synth re-point, fx chain build/reorder/detach, graceful degradation) plus
  `clip_session_test` transport-connection cases; no integration test.
- **Racks surface shell** (issue #209, epic #203, design
  `docs/design/racks-and-voices.md` §8) — the first *user-visible* racks slice: a
  new **Racks** rail entry (between MIDI and Mix) opening a three-pane surface
  (`lib/surfaces/racks/`). A shell-owned `RackDefinitionsController`
  (`lib/engine/state/`, a `ChangeNotifier`) is the panel's single seam over the
  `synth.` / `fx.` / `voice.` registry namespaces and the journaled command layer
  — built whenever a project supplies the registry (no engine dependency), rebound
  on New / Open like the clip-library controller:
  - **Left — `DefinitionsPanel`**: the `synth.` and `fx.` namespaces as two
    independent trees (SYNTHS above, EFFECTS below), flattened into `RackTreeNode`s
    in registry order, each leaf tagged with its kind (`va`, `lowpass`, …). Full
    registry affordances: a per-kind **add** menu (sine · va · fm · sampler for
    synths; one entry per real `FxKind` — the reserved `patcherInsert` is not
    offered — for effects) on each section header and group row, **new group**,
    drag-**reorder** within a section, drag-**regroup** into / out of a group
    (cross-kind drops rejected), **duplicate** (leaf), **rename** (= refactor via
    `MoveEntityCommand`), and **delete** through the `ConfirmDialog` /
    `DeleteImpactDialog` (a synth stranding a `voice.`, an fx an inserting `mix.`
    bus). Every create/move/delete is a `CreateEntityCommand` /
    `CreateGroupCommand` / `MoveEntityCommand` / `ReorderChildCommand` /
    `RemoveEntityCommand` applied + recorded through `ProjectController.recordCommand`.
  - **Center — `DefinitionEditorPane`**: selection (tap a definition) drives it;
    it renders a titled header (`name` + `namespace · kind`) and dispatches the
    body to the per-kind editor (issue #210, `lib/surfaces/racks/editors/`):
    `SineSynthEditor` (voice count), the full sectioned `VaSynthEditor`
    (oscillator stack with add/remove, wavetable, filter, amp + filter envelopes,
    LFO, gain, voice count), `FmSynthEditor` (bank picker, a patch browser listing
    the bank's `patchName`s, algorithm/feedback/transpose, the 6-operator grid),
    `SamplerSynthEditor` (SFZ *or* single-sample recipe + range fields), and
    `FxEditor` (one labelled row per param — universal `impact`/`bypass` plus the
    kind's params from `fxParamsFor`). Rows are shared token-built controls
    (`EditorSection`, `EditorSliderRow`, `EditorNumberRow`, `EditorChoiceRow` over
    `PhiSelect`, `EditorToggleRow` over `PhiToggle`). **Every edit is a journaled
    payload command** through `RackDefinitionsController.updateSynth`/`updateFx`
    (one `UpdateEntityPayloadCommand` recorded via `ProjectController.recordCommand`);
    **continuous sliders gesture-coalesce** — `EditorSliderRow` holds a transient
    value while dragging and commits **once** on pointer-up, so a slider sweep is
    one undoable edit. Two injected seams feed the asset-backed editors: a
    `FmBankReader` (`lib/domain/synth/`, production `Dx7FmBankReader` in
    `lib/engine/bridge/` over `Dx7Bank`) browses a bank's patch names, and a
    `RackAssetSource` (`lib/surfaces/racks/`, production
    `FileSelectorRackAssetSource` = `file_selector` + a `FileAssetImporter` bound
    to the live project location) imports a picked `.syx` / `.sfz` / sample into
    the project's `assets/` folder and hands back the project-relative ref — both
    fakeable, both wired from the shell.
  - **Right — `VoicesPane`**: one **editable** card per `voice.` (issue #211) —
    colour swatch + name + **arm** toggle, an internal / external **kind** toggle,
    the **synth** picker (internal) or **channel** picker (external), the **bus**
    picker (`mix.master` + user buses), and six **colour** quick-picks; a header `+`
    adds a voice, a row `⋯` menu renames (= refactor) / deletes (with impact). Every
    edit threads through `RackDefinitionsController.updateVoice` / `newVoice` (a
    journaled payload command; a re-point also refreshes the back-reference index).
    Below the cards a one-octave **test strip** auditions the armed voice from the
    mouse. See the voices-pane / audition entry below.
  The definitions controller / view-models are unit-tested (`rack_definitions_controller_test`
  — trees, per-kind create, duplicate, rename-refactor, delete-impact, regroup,
  reorder, voices, rebind, **synth/fx decode + `updateSynth`/`updateFx` journaling**),
  the panes + editors widget-tested (`racks_surface_test` — tree + chips render,
  selection → editor routing, per-kind add menus, group, duplicate, rename, delete +
  delete-impact, drag reorder/regroup, null-controller hint; `definition_editors_test`
  — VA slider drag coalesces to one command, wave select, sine voice count, FM patch
  browser populating from a fake bank + patch select + bank import, sampler sample
  import, fx param slider + bypass toggle), and end-to-end `racks_surface` +
  `racks_editors` integration tests drive the real shell (open Racks → select the
  seeded `synth.sine` → edit its voice count → add a VA synth → a real detune-slider
  drag mutates the payload and dirties the project).
- **Voices pane: bind / colour / kind, arm-for-input, test strip, roll audition**
  (issue #211, epic #203, design `docs/design/racks-and-voices.md` §7, §8) — the
  last user-visible racks slice, turning #209's read-only voices scaffold into a
  full editor plus the audition path. **Editing** grows `RackDefinitionsController`
  with `voiceAt` / `updateVoice` (journaled `UpdateEntityPayloadCommand`; because a
  voice payload is a JSON map, not a `ReferenceSource`, a re-point also
  `setReferences` so delete-impact + rename-refactor track the new synth/bus) /
  `newVoice` / `synthDefinitions` / `mixBuses`; `VoicesPane` renders each voice as
  an editable card (kind toggle, synth ↔ channel picker, bus picker, six colour
  quick-picks, arm toggle, `⋯` rename/delete) with a one-octave test strip.
  **Audition** (design §7) is an *immediate* path, bypassing the transport: the
  engine bridge grows `MaterialisedSynth.noteOn`/`noteOff` (internal voices → the
  `Synth` on its channel) and `MidiGateway.sendNoteOn`/`sendNoteOff` (external voices
  → the open MIDI-out), and `EngineMidiController` exposes `auditionNoteOn`/`Off`
  (internal vs external dispatch), `auditionPreview` (a note-on + timed note-off for
  the roll), and an `inputEvents` passthrough. A shell-owned
  `VoiceAuditionController` (`lib/engine/state/`, a `ChangeNotifier`, built only with
  a MIDI subsystem) holds the **single armed voice** (arming another disarms + releases
  the first), subscribes to the parsed MIDI-in stream and plays the armed voice on
  every incoming note (channel ignored — arm overrides routing), and backs the test
  strip's press/release. **Roll audition** (design §7, closing #191's caret-sound
  deferral): `PianoRollEditor` gains an `onAuditionNote` callback fired when a note is
  clicked (selected or added) or stepped in with the caret; `MidiSurface` wires it to
  `EngineMidiController.auditionPreview(note.voice, …)` so a clicked note previews
  through its **routed voice**. Unit-tested (`rack_definitions_controller_test` voice
  editing; `voice_audition_controller_test` single-arm + MIDI-in + strip + release;
  `engine_midi_controller_audition_test` internal/external/preview), widget-tested
  (`voices_pane_test` row editing, kind switch, single-arm, strip; `piano_roll_audition_test`
  the three preview triggers), and an end-to-end `voices_pane` integration test (arm →
  test strip sounds the materialised synth; kind switch to external; a roll click
  previews through the routed voice).
- **Mix INSERTS area: fx placement, reorder, move-with-impact** (issue #212, epic
  #203, design `docs/design/racks-and-voices.md` §5) — the last racks slice, the
  user-visible home for the `mix.inserts` schema (#204) + fx gateway/engine
  (#207/#208) + fx editors (#210). Each leaf strip and group-bus header in the Mix
  surface (`lib/surfaces/mix/mix_surface.dart`) gains an **INSERTS** area beneath
  the strip (mirroring the SENDS area): the bus's ordered `fx.` chain as one row
  per placed effect (name + kind), a `+ insert` `PhiSelect` picker over the fx not
  already on this bus, drag-to-reorder by a per-row grip (`Draggable`/`DragTarget`,
  drop places the dragged insert before the target — the strip-reorder idiom), and
  a per-row `×` remove; hidden entirely when the project defines no fx. Placement
  is a **journaled `mix.` payload edit** the engine's `RackMaterialiser` (#208)
  turns into a live `DspObject` chain on the ensuing re-sync — the surface only
  edits the ordered `inserts` list. The **one-bus invariant** (racks §5): the
  picker annotates an fx already on another bus (`big_delay · on drums`), and
  choosing it **moves** it — a `ConfirmDialog` names the losing bus, then the
  engine removes it there and appends here (each its own journaled command). New
  `PhiEngine` surface (all reading/writing the strip payload through the shared
  `_persistStripPayload` de-dupe): `channelInserts` / `availableFxFor` /
  `busHoldingInsert` / `fxKindOf` (reads) and `addChannelInsert` (append + move) /
  `removeChannelInsert` / `moveChannelInsertBefore` (edits). Live-code addressing
  is already satisfied — fx params reach by entity address through the registry
  (`fx.big_delay`), so no new seam here. Reverb stays engine-default (no UI, §9);
  the master strip and returns carry no inserts (no backing `mix.` strip / out of
  the issue's "strip + group-bus header" scope). Covered by unit tests
  (`engine_mix_inserts_test` — read surface, add/remove, move-with-impact,
  reorder, journaling), widget tests (`mix_inserts_test` — place from the picker,
  drag reorder, remove, the move confirm + its cancel), and an end-to-end
  `mix_inserts` integration test (place three, reorder, move across strips → save
  → reload restores each bus's chain in order).
- **Patcher domain foundation** (issue #218, patcher epic, design
  `docs/design/patcher.md` §3) — the pure-Dart entities the patcher epic binds on,
  a new `patch.` registry kind (`RegistryKinds.patch` + `defaultEntityCodecs()`),
  TDD, no user-visible surface. **The payload is the engine dump.** `PatchPayload`
  (`lib/domain/patcher/`) wraps the engine `dumpJson` (graph *and* layout — node
  positions ride in the object GUI properties the shipped gateway writes) under a
  `dump` key; there is **no parallel Phi-side graph model**. It compares by value
  (a deep, order-independent JSON compare over the opaque dump) so a round-trip
  asserts identity, and — a patch references no other entity — it is **not** a
  `ReferenceSource`. `PatchCodec` (schema v1) keeps it map-native, the same journal
  contract the `mix.`/`fx.` codecs honour. **Edits are journaled gesture commands.**
  A pure-domain `PatchEditGateway` seam names the incremental patcher operations
  (create / restore / remove / connect / disconnect / move / setParam, plus the
  reads a reversible delete captures) that the engine's per-entity gateway will
  implement (epic issue 2); six `ProjectCommand`s in `lib/domain/patcher/commands/`
  forward one gesture each and `revert` its inverse — `AddObjectCommand`,
  `DeleteObjectCommand` (captures the object spec + its cables so undo restores
  both), `ConnectCommand`, `DisconnectCommand`, `MoveNodeCommand`,
  `ParamChangeCommand` — each `entitiesTouched` = the `patch.` address (so save
  re-dumps it) and `toJson`-serialisable for the journal. `restoreObject` recreates
  a deleted object under its **same id** so cables and later gestures stay valid
  across an undo/redo cycle. Value types `PatchPoint` / `PatchConnection` /
  `PatchObjectSpec` (`lib/domain/patcher/`, pure Dart — no `dart:ui`) are the
  gesture vocabulary; the old Flutter-coupled `PatchGraph`/`PatchNode` demo-canvas
  model is untouched (the surface rework is a later epic issue). The **back-reference
  seam** rides the registry's existing generic index: a future `fx.` placement of
  kind `patcherInsert` wrapping a `patch.` reference registers, so delete-impact
  lists it. Pure-domain issue (no surface, no gateway wiring), so — like #204 —
  covered by unit tests via a `FakePatchEditGateway` test double (payload/codec/
  value-type round-trips, every command apply/revert incl. LIFO undo of a mixed
  stack) plus a `patch_round_trip` acceptance test (store save/load identity +
  delete-impact surfaces the placement referent, in memory and after reload); no
  integration test. Gateway generalisation, entity↔instance reconciliation, and the
  surface are the following epic issues.
- **Patcher engine reconciliation + source placement** (issue #220, patcher epic,
  design `docs/design/patcher.md` §3, §4, §8) — the engine-side counterpart of
  #218/#219 that materialises a live native patcher per open `patch.` entity. A new
  `PatchReconciler` (`lib/engine/state/`) is the patcher analogue of the `mix.`
  channel sync and the `RackMaterialiser`: it `sync`s one [PatcherGateway] instance
  per `patch.` entity — **parsing the payload dump on open**, keyed by address so a
  survivor keeps its live native graph across an unrelated re-sync — and tears the
  instance down on delete/close. **Source placement lifecycle:** `PatchPayload`
  grows a `placement` field (the `mix.` bus, a *soft* pointer — the patch is still
  not a `ReferenceSource`); the reconciler mounts a placed patcher as a `Sound`
  (`mountAsSource`) on that bus, `start`ed/`stop`ped explicitly. Placement persists;
  running state does **not**, so a loaded project starts silent (consistent with
  clips). A running source is kept mounted on its current bus across re-syncs; a
  placement naming a bus absent from the live mix **degrades gracefully** — the
  source is left unplaced and a `PatchPlacementNotice` surfaces through
  `PhiEngine.lastPatchNotice` (the `AudioDeviceNotice` shape). **Dump-to-payload on
  save:** the reconciler's `flushToPayloads` re-dumps each open patcher into its
  entity payload (via `UpdateEntityPayloadCommand`, only when the dump changed),
  wired to a new `ProjectController.onBeforeSave` hook the shell sets to
  `PhiEngine.flushPatchPayloads` — so save/autosave captures the *live* patch, not
  the last-loaded one, with dirty-tracking carried by the gesture commands (the
  surface epic applies them). `PhiEngine` exposes `patches` / `patchesOrNull`,
  `startPatchSource` / `stopPatchSource` / `flushPatchPayloads`, and `lastPatchNotice`;
  the reconciler is created on `start`, synced at the tail of the channel sync (bus
  ids resolve first), and torn down on project swap / stop. Covered by unit tests
  (`patch_reconciler_test` — open/edit/save round-trips, mount/unmount/start/stop,
  teardown on delete, graceful degradation; `patch_payload_test` placement cases),
  an engine wiring test (`engine_patch_reconciliation_test`), a `ProjectController`
  `onBeforeSave` hook test, and an end-to-end `patch_source_persistence` integration
  test (edit a live patcher → save → reload re-materialises the edited patch,
  placement intact). The surface + the gesture-command edit adapter are following
  epic issues.
- **Patcher palette + reference panel** (issue #221, patcher epic, design
  `docs/design/patcher.md` §5) — the epic's first UI slice, driven entirely by the
  gateway metadata. A left `PatcherPalette` (`lib/surfaces/patcher/palette/`) reads
  `PatcherController.objectTypes()` (the gateway's `PatchObjectDescriptor`
  passthrough), groups the catalogue into `PatchObjectCategory` sections, filters
  live on name + description, and draws DSP (`~`) entries in the cool accent vs
  control (`.`) grey; the subpatch type is already filtered upstream (§10 decision
  2). Each entry is a `Draggable<PatchObjectDescriptor>` — **drag-to-create**
  resolves the drop point to canvas-local coords through the live pan/zoom
  transform and creates the object there via a new `PatcherController.addObject`
  (documented default args from the descriptor's params, ports read back from
  `inspect`, box sized to fit — reusing a hand-authored body's `defaultSize` when
  the type has one). A right `PatchReferencePanel` (`lib/surfaces/patcher/reference/`)
  renders the engine's own documentation for the selected palette entry **or a
  tapped canvas node** — description, per-inlet accepted-kinds + range, per-outlet
  data type + range, creation params + defaults; no hardcoded catalogue.
  `PatcherNodeView` now headers from the node's own title and renders a
  hand-authored body only when the type has one (else empty), so any dropped engine
  object lands as a real node rather than an error placeholder. Covered by palette +
  reference-panel widget tests (sections, search on name/description, subpatch
  absent, DSP accent, full-metadata render, empty state), surface widget tests
  (drag-create landing a node at the drop point; tap-a-node → reference), and an
  end-to-end `patcher_palette` integration test (summon → sections → tap-to-document
  → drag-create). Per-node live GUI bodies / params dialog are a following epic issue.
- **Patcher canvas interactions** (issue #222, patcher epic, design
  `docs/design/patcher.md` §6) — the canvas rework that makes the surface editable.
  **Body dragging** replaces the old select-an-outlet-first move: a drag anywhere on
  a node moves it (and the rest of the selection) live, committing one
  `MovePatchNodesCommand` on release. Since issue #352 the drag — like select,
  double-click and the marquee — is driven from the canvas's own raw `Listener`
  rather than recognisers on the nodes: a `GestureDetector.onPan` only accepts after
  ~18px and then discards that distance, so the node lagged the pointer and short
  drags did nothing. The canvas measures **scene-space** deltas from the press point
  (so the zoom scale is already divided out), starts the drag at its own 4px click
  slop, and only counts *movement-free* presses towards a double-click. Nodes whose
  descriptor sets `interactiveBody` (fader, number field, message box) keep their
  own gestures — the canvas ignores presses inside their body, so they are dragged
  by the header. `PatchGraph` re-broadcasts each `PatchNode`'s own notifications, so
  a move (drag preview, undo, redo) actually repaints the canvas and its cables.
  **Typed cables:** a drag from an outlet colours
  the ghost by the outlet's `OutType` (`patchOutletColor`, `lib/surfaces/patcher/`),
  compatible inlets light up, and an incompatible drop is refused with a visible
  reject banner — compatibility is a pure `patchPinsCompatible`
  (`lib/engine/bridge/patch_pin_compatibility.dart`, buffer→DSP inlet, float/int
  interchangeable, etc.) over the catalogue's `accepts` mask + `isDspInput`, exposed
  on the controller as `outletTypeOf` / `inletAcceptsOf` / `canConnect` (the low-level
  `connect` stays permissive for the seed). Clicking a cable selects it (bezier
  hit-test via `PatchCableGeometry`); `Delete` removes it. **Selection** rides the
  `PatchGraph` (a node set + an optional cable): click / shift-click / marquee over
  empty canvas; `Delete` removes selected nodes with their cables; `Ctrl+D`
  duplicates the selection (objects + intra-selection cables, offset one grid step).
  Every mutation is a `ProjectCommand` on the controller's per-surface `undoScope`
  (`lib/engine/state/patcher_commands/` — move / connect / delete-cable /
  delete-nodes / duplicate), so `Ctrl+Z/Y` walk them; a delete's undo restores each
  object under its **same logical id** (the controller decouples `PatchNodeId` from
  the churning native handle via an id map), keeping cables and lower undo commands
  valid. The canvas hosts the scene in a plain pan/zoom `Transform` (not an
  `InteractiveViewer`, whose scale recogniser swallowed node/cable drags): middle-drag
  pans, the wheel zooms, a left-drag over empty canvas marquees, and the surface takes
  keyboard focus on release (after the pane's own grab) so the editor keys land.
  Covered by unit tests (compat, graph selection, and every gesture command's
  apply/undo/redo incl. logical-id stability across a delete), canvas widget tests
  (body drag, compatible/incompatible cable drops, cable delete, marquee + shift-click,
  delete-with-cables, duplicate — each with undo/redo, plus the #352 drag regressions:
  1:1 tracking on screen under the touch slop and while zoomed, select-then-drag,
  a press beside an outlet, and a GUI body keeping its own press), and an end-to-end
  `patcher_canvas` integration test (drag · delete-with-cables · duplicate, all undo,
  with the dragged node's rendered header asserted to travel exactly as far as the
  pointer).
- **Patcher node internals** (issue #223, patcher epic, design
  `docs/design/patcher.md` §7, §10 decision 3) — **live GUI bodies** + a
  **metadata params dialog**. The gateway grows two calls consumed FFI-free by the
  surface: `guiValue` (yse's live display value) and `setParams` (reconfigure an
  object's creation args); the controller wraps them as `guiValueOf` / `argsOf` /
  `setNodeParams` plus the undoable `applyParams`. Five control objects are now
  **operable directly on the canvas** (bodies under `lib/surfaces/patcher/nodes/`,
  registered in `patcher_node_types.dart`): the generalised `.slider` (a `PhiFader`,
  its readout the object's `guiValue`), `.t` toggle (`PhiToggle` → `sendFloat` 1/0),
  `.b` button (a bang → `sendBang`), `.i`/`.f` number (an editable readout that pushes
  `sendFloat` then re-reads `guiValue`, so it shows the authoritative engine value —
  a cable into its inlet would set the same), and `.m` message (its args, fired as a
  bang on tap). Non-GUI nodes get a **double-click params dialog**
  (`params/patch_params_dialog.dart`) — one field per documented `PatchParamDescriptor`
  (name · doc · default · range), seeded from the node's current args, joined back into
  a positional arg string and applied through `setParams` as a single
  `SetPatchParamsCommand` on the surface `undoScope` (so the whole edit round-trips
  under one Ctrl+Z) — the same metadata-driven-editor pattern as the MIDI transform
  editors. Double-click is detected from raw pointer timing in the canvas (a nested
  `GestureDetector.onDoubleTap` would delay the node's single-tap select), gated to
  non-GUI types (GUI objects are operated live). Covered by unit tests (controller
  `guiValueOf` / `setControlBang` / `applyParams` undo/redo + unknown-handle
  tolerance), widget tests (each body's interaction reaching the fake gateway,
  the number body's `guiValue` display refresh, the dialog round-tripping a fake
  type's params with undo), and an end-to-end `patcher_node_gui` integration test
  (operate the seeded slider → `sendFloat`; double-click `~sine` → edit frequency →
  `setParams` into the live patch).
- **Patcher entity strip + source-on-bus placement** (issue #224, patcher epic,
  design `docs/design/patcher.md` §3, §4, §8) — the slice that joins the surface
  (which until now edited a single hardwired demo patcher) to the per-entity world
  #218–#220 built. A new `PatchLibraryController` (`lib/engine/state/`, the patcher
  analogue of `ClipLibraryController`) drives an **entity strip**
  (`lib/surfaces/patcher/library/patch_entity_strip.dart`) over the `patch.`
  namespace: a collapsible tree (groups + ordering) with the standard affordances —
  new / duplicate / rename (= refactor) / delete (impact dialog) / new group /
  drag-regroup / reorder — each a journaled registry command via a pure-domain
  `PatchLibrary` (`lib/domain/patcher/`, `newPatch` / `duplicate`) or the shared
  registry commands, recorded through the project controller like every other edit.
  **Opening** a patch (one at a time in v1) binds a cached `PatcherController.bound`
  editor to the [PatchReconciler]'s **live native instance** for that entity
  (`instanceIdOf`) — the surface edits the *same* patcher the reconciler mounts, so
  the editor never owns the instance and switching leaks nothing (cached editors are
  disposed only on delete / project swap, never touching the reconciler's native
  patcher). `PhiEngine.patcher` is now the *open* editor; the engine seeds a default
  `patch.` entity when a patcher-enabled project carries none (the entity-strip
  analogue of the demo clip seed) and opens it, so existing surface flows keep a
  patch to edit. **Source placement:** a `PatchPlacementBar`
  (`lib/surfaces/patcher/placement/`) pairs a `PhiSelect` over the placeable mix
  buses (`PhiEngine.patchBusOptions` → master + strips + group buses + returns as
  `PatchBusOption`s) with a start / stop toggle; picking a bus records the placement
  in the payload (`UpdateEntityPayloadCommand`, so it persists + journals) and
  re-syncs the reconciler, start / stop mount / unmount the source through the
  reconciler. Placement persists; running state does not (a loaded project starts
  silent); unplaced patches stay editable silently. Covered by unit tests
  (`patch_library_test`, `patch_library_controller_test` — tree, open/switch with no
  instance leaks, every affordance, placement + start/stop + persistence), widget
  tests (`patch_entity_strip_test`, `patch_placement_bar_test` — each affordance and
  the placement UI against the fake gateway), and an end-to-end
  `patcher_entity_strip` integration test (switch patches → place on master →
  start/stop; a placement round-trips a save/reload). **v1 limitation, resolved in
  #308:** opening a patch loaded from disk (or renaming the open one) showed an
  empty canvas until edited — the editor's node mirror wasn't rebuilt from the
  reloaded engine dump; the audio (reconciler-materialised graph) was unaffected
  either way.
- **Patcher as an insert effect** (issue #225, patcher epic, design
  `docs/design/patcher.md` §4 role 2, §11; the last slice of the epic) — the
  reserved `fx.` kind `patcherInsert` (racks §5) becomes real, wiring a patcher
  into a mix bus's insert chain through the existing racks seam. `FxDefinition`
  (`lib/domain/fx/`) gains an optional `patch` reference and is now a
  `ReferenceSource`: a `patcherInsert` fx wraps a `patch.` entity by address, so
  `fx → patch` is a back-reference edge (delete-impact on the patch lists its
  insert wrappers; a patch rename refactors the wrapper). The engine materialises
  it as a `DspObject.patcherInsert` that **borrows** the patch's live native
  patcher — so the same graph the editor edits is heard live through the insert. A
  new bridge `PatcherInsertSource` seam (`lib/engine/bridge/`, implemented by
  `RealPatcherGateway`) hands the fx gateway that native `Patcher` by instance id;
  `FxGateway.materialiseFx` gained a `patchInstanceId`, and a patcher-insert handle
  is placeable only while its patcher resolves (else the chain skips it, like the
  old reserved stub). The `RackMaterialiser` resolves the wrapped patch's instance
  through a seam and rebuilds the handle when it appears / vanishes. To keep the
  live chain safe, `PhiEngine._syncChannelsFromRegistry` now runs the patcher
  subsystem in **two phases** around the rack sync — `PatchReconciler.materialise`
  (create patchers so a chain can borrow one), then `_racks.sync`, then
  `PatchReconciler.teardownRemoved` (free a deleted patch's native patcher only
  after the chains that borrowed it have been detached), so no wrapper ever links a
  freed patcher. **Placement UI:** the mix INSERTS picker (#212) additionally
  offers each patch with no wrapper yet as `patcher · {name}` — picking it creates
  the wrapping `fx.` entity (`PhiEngine.addPatchInsert` / `availablePatchesToInsert`)
  and places it, after which it obeys the same one-bus move-with-impact + reorder
  as any other insert (a placed patch's wrapper then flows through `availableFxFor`,
  not the patch list, so the two are never double-offered). `_persistInserts` now
  re-points the leaf strip's back-reference index on every insert edit (the mirror
  of `updateVoice`), closing the `mix.inserts → fx` edge for the live command path
  so deleting an inserted wrapper lists the bus. Covered by unit tests
  (`fx_definition_test` patch reference / references / refactor round-trips;
  `engine_patcher_insert_test` — create + place, materialisation into the chain
  borrowing the live instance, delete-impact both directions, removing the patch
  drops the insert, reorder / move), a widget test (`mix_patcher_insert_test` — the
  picker offers a patch, picking creates + places the wrapper, a wrapped patch drops
  off the offer), and an end-to-end `mix_patcher_insert` integration test (pick a
  patcher insert in the real app → both-direction delete-impact → save → reload
  restores the insert and its `fx → patch` reference).
- **Patcher: rebuild the editor canvas from a reloaded dump** (issue #308, patcher
  epic follow-up to #224) — closes the v1 gap where opening a patch **loaded from
  disk**, or **renaming** the open one, showed an empty canvas until edited: the
  reconciler had parsed the dump into the live native instance, but the editor's
  Dart-side mirror started empty. The `PatcherGateway` gains an **object-enumeration**
  seam — `enumerate(instanceId)` returns a `PatcherGraphSnapshot` (every object's
  handle id · type · args · stored position · port topology, plus every connection
  in native handle-id terms). The capability was already in the `dart-yse` wrapper
  (`PHandle.type` / `.params`, `Patcher.objects` / `getHandleAt`, and the
  `connectionCount` / `connectionTargetId` / `connectionTargetInlet` introspection),
  so `RealPatcherGateway` builds it FFI-side with no new `dart-yse` call. A new
  `PatcherController.rebuildFromInstance()` reconstructs the `PatchGraph` +
  `_nativeByNode` / `_argsByNode` from that snapshot — cables wired straight into
  the mirror (the native connections already exist, so no `connect` is re-issued),
  node voice defaulting to 1 (not carried in the dump). `PatchLibraryController.open`
  calls it when it first binds an editor to a reconciler instance, so opening a
  loaded patch — or the rename path (flush → move → re-materialise → re-open) —
  shows the graph at once; the surface's demo-seed stays `initState`-only, so a
  reopened non-first patch is never re-seeded over its loaded graph. The
  `FakePatcherGateway`'s `dumpJson` / `parseJson` were upgraded to a **structured,
  re-parseable** round-trip (was a bare `{objects:N,cables:M}` summary) so the fake
  faithfully models a reload; `enumerate` reads the live instance the same way the
  real one does. Covered by gateway unit tests (`enumerate` objects / connections /
  scoping / empty; dump→parse→enumerate round-trip), `PatcherController` rebuild
  tests (nodes · ports · args · positions · cables · idempotency · no re-issued
  connects · id-map wiring), `PatchLibraryController` tests (open a loaded dump
  rebuilds the canvas; rename re-materialises it), and an end-to-end
  `patcher_reload_canvas` integration test (duplicate the seeded patch → the copy
  opens with its three-node graph rebuilt, not a blank canvas).
- **The `phi` live-coding library core** (issue #230, live-coding epic, design
  `docs/design/live-coding.md` §3–§4) — the friendly object layer the Code
  surface will run, shipped as **plain Python source** in the repo under
  `python/phi/` (review decision 4; not Dart, not under `lib/`). Dot-access
  namespaces (`voice` · `clip` · `mix` · `fx` · `patch` · `domain` · `var` ·
  `state`) are `__getattr__` proxies over a name table; group proxies nest
  (`clip.drums.intro_fill`), iterate, and carry group verbs, and `dir()`
  reflects the table for completion parity. A proxy references a mutable table
  **entry**, never an address string, so a bound proxy (`pad = voice.bells`)
  **follows a rename** when `_sync` mutates the entry in place ("resolve once,
  bind the object"). The host-facing `_sync` protocol is full-table replace plus
  incremental create / rename / regroup / delete (issue #231 will drive it from
  the `RegistryMirror`). The verb skeleton is verb-first —
  `play`/`stop`/`pause`/`loop` (clips, groups), `note`/`off` (voices),
  `set`/`fade` (mix, fx, patcher slots), `fire` (state), `every`/`after` (sugar
  over `yse.schedule`) — each emitting on one of the two planes (design §4),
  invisible at the call site: **engine-direct** for mix/patch
  (`channel.<addr>.volume` / `patcher.<addr>.<slot>`) and **host-mediated**
  `phi.ctl.*` for everything structural (clip/voice/state/var/domain/fx), which
  the bus tap (#229) and control plane (#233) will dispatch. The module
  `install`s its namespaces into a script's global scope and registers under
  `sys.modules['phi']` so `import phi` works; the actual boot exec over
  `LiveCoding.run` lands with the real evaluator (#232). No Dart `lib/` code and
  no user-visible surface yet. Covered by a pure-Python `unittest` suite under
  `python/tests/` (a fake `yse` bus records every publish, so each test submits
  verbs and asserts the exact emitted address/value) — table sync,
  rename-following bound proxies, group iteration, every verb shape, and the
  bootstrap — driven inside `flutter test` by a Dart harness
  (`test/engine/python/phi_library_test.dart`) that runs the suite through the
  system Python (skipped only if no interpreter is on PATH; CI's Ubuntu runner
  always has `python3`).
- **`RegistryMirror` becomes real** (issue #231, live-coding epic, design
  `docs/design/live-coding.md` §3) — the no-op seam #125 shipped gains a live
  implementation. `lib/engine/bridge/real_registry_mirror.dart` turns each
  registry lifecycle change into a `phi._sync_*(...)` script and pushes it
  through the shared `CodeEvaluator`: `onCreate`/`onDelete`/`onRename`/`onRegroup`
  map 1:1 onto the library's incremental sync functions (#230), and a new
  `RegistryMirror.syncAll(addresses)` pushes a full `phi._sync_replace([...])`.
  Pushes are submitted synchronously in event order onto the same evaluator queue
  the Code surface runs user blocks on, so a script run right after a rename sees
  the renamed table. Every kind is forwarded verbatim; the `phi` library now
  ignores kinds it does not model (`synth.`, …) in its incremental ops too — the
  same tolerance `_sync_replace` already applied — so the mirror needs no per-kind
  knowledge. `RegistryMirrorBinder` gains `resync()` (a pre-order snapshot of every
  node across kinds → `syncAll`), and `PhiEngine` drives it at the **boot** full
  sync (end of `start`, and again after a `stop → start` re-inits the `System`,
  blanking the embedded Python — the **re-init re-sync**) and on every
  `bindProject` swap. Production still wires the `NoOpRegistryMirror`; hanging the
  real mirror on the shell's live evaluator lands with the real evaluator (#232).
  Covered by unit tests (the real mirror's emitted script for each op + ordering +
  a swallowed rejected push; the binder's `resync` traversal), engine wiring tests
  (boot / re-init / project-swap full syncs, and the real mirror over a fake
  evaluator emitting the actual `_sync_*` scripts end-to-end), and a Python module
  (`python/tests/test_mirror_scripts.py`, run by the same Dart harness) that
  `exec`s the literal mirror-emitted strings — bound-proxy rename-following, the
  blank-interpreter `_sync_replace` re-sync, and unmodelled-kind tolerance.
- **The `phi.ctl` control plane** (issue #233, live-coding epic, design
  `docs/design/live-coding.md` §4) — the host-side counterpart to the mirror:
  where `RealRegistryMirror` pushes host→interpreter, `ControlPlaneDispatcher`
  (`lib/engine/bridge/control_plane_dispatcher.dart`) routes interpreter→host.
  It subscribes to the `BusTap` (#229) `phi.ctl` prefix, decodes each tapped
  `(address, value)` frame, and dispatches to the owning controller: clip
  play/stop/pause/loop + group verbs + namespace-wide stop-all, voice note/off
  (the immediate audition path), `var.x = v` assignment, `state[.<machine>].fire`,
  `domain.<d>.tempo`, and (since #316) host-mediated `fx.<addr>.<param>` param
  sets. Each controller is reached through a small **port** interface
  (`ClipControlPort` · `VoiceControlPort` · `VariableControlPort` ·
  `StateControlPort` · `TempoControlPort` · `FxControlPort`), so the dispatcher is
  testable standalone against fakes. Malformed frames, unknown namespaces, unknown
  verbs, and wrong-typed values **degrade gracefully** — a `ControlPlaneNotice`
  (logged via `debugPrint` by default), never a throw, guarded so a bad frame
  never tears down the subscription. Covered by `control_plane_dispatcher_test.dart`
  — every verb's dispatch to a fake controller, the graceful-degradation paths, and
  an end-to-end fake flow. The Python emission side is unchanged (already shipped +
  tested by #230's `test_verbs.py`).
  **Production activation** (issue #334): `PhiEngine.start` now constructs the
  dispatcher over the engine's own `tapBus` seam with the **real** ports — `state`
  via `StateMachineControlPort(stateTriggers)`, `var` via
  `RuntimeVariableControlPort` over the runtime registry, `domain tempo` via
  `DomainTempoControlPort` (the same live-override seam a fired state's tempos
  slice applies through, `_applyDomainTempo` — sessions re-pace, a bound metronome
  click re-paces), `clip` via `SessionClipControlPort` over the session manager
  (play/stop/pause/loop/stop-all, with the **open-from-registry** step for a clip
  with no open session yet), and `voice` via `AuditionVoiceControlPort` over the
  racks audition path (tracking held notes so a bare `off()` releases them all).
  The adapters live in `lib/engine/state/`, tolerate an absent MIDI subsystem, and
  no-op gracefully on unknown targets. The `fx` leg is decoded and routed but its
  real fx-param controller is deferred (issue #348) — production wires a
  no-op `_UnwiredFxControlPort` for now. Still silent in production until the tap C
  API lands (the default `NoOpBusTap` yields no frames, mirroring #229's
  present-but-silent seam), but live the moment a frame arrives. The dispatcher is
  torn down first on `stop`, cancelling its subscription before the controllers it
  routes to. Covered by unit tests for each adapter (`lib/engine/state/*_control_port`)
  and an end-to-end `control_plane_activation_test.dart` that drives a fake tap
  through the *engine-constructed* dispatcher — no test scaffolding — to each real
  port (state fire, var move, domain override, clip play, voice note/off).
- **The diagnostics log domain** (issue #268, epic #267, design
  `docs/design/diagnostics.md` §2, §6) — the pure-Dart foundation for the unified
  log, seams + fakes, no UI yet (the panel is #270, source wiring #269). A
  `LogEntry` (`lib/domain/log/`) tags each line with its `LogSource`
  (engine / python / app) + `LogLevel` (debug → error) + injected time + text,
  and `format()`s to one plain readable file line. A `LogStore` (ChangeNotifier)
  is the ~2000-entry ring buffer the panel will watch, dropping the oldest when
  full. `SessionLog` mirrors the store to `%APPDATA%/phi/logs/phi-<timestamp>.log`
  over a `LogFileStore` seam (`RealLogFileStore` on `dart:io`, faked in tests):
  `boot` opens the session file, prunes to the newest 20 sessions, and turns the
  **clean-shutdown marker** into crash detection — a marker *present* at boot means
  the last session exited cleanly (it is consumed), *absent* means it crashed, so
  `boot` returns a `CrashReport` pointing at the previous session's log (design §6);
  `close` writes the marker at orderly shutdown. Time comes from a new `Clock`
  seam (`lib/core/`, `SystemClock` in production) — no `DateTime.now()` in the
  domain. Covered by unit tests (entry format/equality, ring-buffer eviction +
  notification, marker lifecycle + crash detection + retention against a fake
  filesystem) and a real-filesystem round-trip test of the `dart:io` store and a
  full boot/append/close cycle.
- **Log sources + the notice channel** (issue #269, epic #267, design
  `docs/design/diagnostics.md` §2, §3, §8 decision 3) — wires the three sources
  into the #268 store and adds the shared "surfaced notice" home. A pure-Dart
  `LogRecorder` (`lib/domain/log/`) is the single write path: it stamps each entry
  off the injected `Clock`, appends to the `LogStore`, and — once booted — mirrors
  it to the `SessionLog` file (fire-and-forget; entries predating boot stay in the
  ring buffer only). Sources: the **engine** stream rides a new bridge seam
  (`EngineLogSource` — `RealEngineLogSource` forwards yse's `Log.messages`,
  subscribing replaces yse's own file sink; `NoOpEngineLogSource` for a bare
  engine), exposed as `PhiEngine.engineLogMessages`; the **Python** interpreter's
  tracebacks are read off the Code evaluator's `EvalStderr` frames (the same stream
  the Code strip renders — two consumers). A shell `LogCoordinator`
  (`lib/shell/diagnostics/`) subscribes both into the recorder, classifying
  level-less engine lines via a pure `engineLogLevel` heuristic. The **notice
  channel** is `NoticeCenter.notice(message, {level})` — one call shows a transient
  toast (`ToastController` + `PhiToastOverlay`/`PhiToast`, bottom-centre,
  non-interactive) *and* writes an app-sourced log entry, the single home for every
  design's "surfaced notice". The **retrofit sweep** points the shipped ad-hoc
  notice sites at it: the `Workstation` listens to the engine's `lastAudioNotice`
  (device fallback — `noAudioDevice` at error, else warning) / `lastStateNotice` /
  `lastPatchNotice` degradation notifiers and surfaces each through the channel
  (a grep-assert test keeps `lib/` free of direct `SnackBar` / `ScaffoldMessenger`
  sites). The production entry point (`PhiApp`) boots a `SessionLog` over
  `RealLogFileStore` so entries land on disk, closing it with the clean-shutdown
  marker on exit (crash *surfacing* of that file is #272). Covered by unit tests
  (recorder stamping + source/level + guarded file mirror, level heuristic, log
  coordinator, toast controller, notice-center toast+log pairing), a
  `PhiToastOverlay` widget test (render, auto-dismiss, click-through), the sweep
  grep-assert, and an end-to-end `notice_channel` integration test (a device
  fallback toasts *and* logs through the real app; a Python traceback lands at
  error level).
- **The log panel drawer** (issue #270, epic #267, design
  `docs/design/diagnostics.md` §4, §5) — the bottom-drawer log built on the #268
  store, above the status bar. A pure-Dart `LogFilter` (`lib/domain/log/`) is the
  combinable query — a minimum level (this level and above), an included-source
  set, and a case-insensitive text search, all AND-ed in one `apply` pass — and
  `LogTranscript.of` renders a run of entries to paste-ready text (the session-file
  line shape; reusable by #272's report bundle). A shell `LogPanelController`
  (`lib/shell/diagnostics/`, ChangeNotifier over the shared `LogStore`) owns the
  open state, the live filter, copy (through an injectable clipboard seam), and the
  **status-bar error badge** — the count of error entries recorded *while the drawer
  was closed* since it was last open, accrued by diffing the store's tail (a ring
  rollover can only under-count, never invent). `LogPanel` is the drawer: entries
  render newest-*last* with **auto-follow** (a `ScrollNotification`-driven follow
  flag pinned to the bottom; a user drag up pauses it and reveals a jump-to-newest
  pill; a drag back or the pill resumes), a `LogFilterBar` of level/source chips +
  a search field, a `SelectionArea`-wrapped list for drag-select copy, and header
  copy / clear-filters / close. `LogPanelToggle` sits in the `BottomStatus`: it
  toggles the drawer, lights while open, and badges the unseen-error count —
  tapping it *with* a badge opens filtered to errors and clears (design §5). A
  `view.log` command (Ctrl+J, a layout-named logical key) shares the plain-toggle
  path with the toggle and palette. Covered by unit tests (`LogFilter` predicates +
  equality, `LogTranscript`, `LogPanelController` badge accrual/clear/rebase +
  filter mutations + copy), widget tests (`LogPanel` follow/pause/jump, every
  filter combination, search, copy output, empty state, close; `LogPanelToggle`
  badge display + tap-opens-to-errors), the `shell_commands` Ctrl+J assertion, and
  an end-to-end `log_panel` integration test (toggle + Ctrl+J open, filter/search
  narrow, copy writes the visible set, the error badge opens filtered to errors and
  clears).
- **The status-bar audio-device chip** (issue #271, epic #267, design
  `docs/design/diagnostics.md` §5) — a glanceable health chip in the `BottomStatus`
  showing ok · reconnecting · lost. An `AudioDeviceHealth` enum
  (`lib/shell/diagnostics/`) plus an `AudioHealthMonitor` (same folder) derive the
  state on the engine's existing telemetry tick: a live device (`activeAudioState()`
  reads `sampleRate > 0`) is ok, a drop with a standing `noAudioDevice` notice is
  lost, and a drop otherwise (the 1 s auto-reconnect window) is reconnecting —
  reaching ok clears the tracked cause so a later drop reads as a fresh reconnect,
  not a stale loss. The monitor is built from existing engine API only
  (`telemetry` + `activeAudioState()` + `lastAudioNotice`, no engine change) and
  logs every *transition* through the notice channel (design §5): dropping to
  reconnecting/lost raises a notice (toast + log at warning/error), recovery to ok
  logs at info without a toast. `AudioDeviceChip` (`lib/shell/bottom_status/`)
  watches the monitor's `ValueListenable<AudioDeviceHealth>` — calm/muted while ok,
  amber reconnecting, red lost — and clicks through to the settings dialog's AUDIO
  section (a new `initialSection` on `SettingsDialog.show`). The `Workstation` owns
  the monitor and wires the chip + click-through; `BottomStatus` gains optional
  `audioHealth` + `onAudioSettings` params (omitted in the bare widget tests, so the
  chip is only shown when wired). Covered by `AudioHealthMonitor` unit tests
  (ok→reconnecting→lost→ok derivation + paired log entries + toast/no-toast), an
  `AudioDeviceChip` widget test (per-state look + click-through), and an end-to-end
  `audio_device_chip` integration test (the real app walks the four states via the
  fake gateway, each transition logs, and the chip clicks through to settings AUDIO).
- **The report bundle + crash surfacing** (issue #272, epic #267, design
  `docs/design/diagnostics.md` §6) — closes the diagnostics epic. A pure-Dart
  `DiagnosticsBundle` (`lib/domain/log/`) renders one paste-ready, **stable-ordered**
  block from already-resolved primitives — app + libYSE versions, the resolved
  `YSE_DLL_PATH`, the active device + live audio state (rate/buffer/latency/layout),
  the audio-stall counters, the open project path, and the last 200 log lines
  (reusing `LogTranscript`) — so two reports taken days apart diff cleanly; nothing
  is redacted (single-user, local machine). A shell `DiagnosticsReport`
  (`lib/shell/diagnostics/`) is the single seam that gathers those facts off the
  engine façade, the shared `LogStore`, and the open project location, and it backs
  **both** the new `Copy Diagnostics` palette command (`app.copyDiagnostics`, no
  chord) and the settings DIAGNOSTICS copy button (the section gained an optional
  `report` builder; without it, the bare read-only block is still copied). The app
  version is a plain `phiAppVersion` constant (`lib/core/app_version.dart`), kept in
  step with `pubspec.yaml` — no `package_info_plus` plugin for a local instrument.
  Crash surfacing rides on the #268 marker/`CrashReport`: `SessionLog.boot`'s verdict
  (a missing clean-shutdown marker ⇒ the previous session crashed) is now captured in
  `PhiApp` and handed to the `Workstation` as a `Future<CrashReport?>`; on first frame
  a non-null report raises a warning notice (toast + log) naming the previous session's
  log file — **alongside**, not replacing, the journal's recovery dialog. Covered by
  `DiagnosticsBundle` unit tests (complete + stable order + log tail + empty/no-device/
  no-project fallbacks), a `DiagnosticsReport` test over the real engine + log, a
  `DiagnosticsSettingsSection` widget test (the supplied bundle wins over the read-only
  rows), and an end-to-end `diagnostics_bundle` integration test (the `Copy Diagnostics`
  command writes the bundle to the clipboard; an injected crash report surfaces the
  linking notice + log entry).
- **What `DROPS` actually counts** (issue #350) — the chip used to render the
  engine's `missedCallbacks` raw, which is neither cumulative nor a tally of
  callbacks that missed a deadline: `system::update` bumps it on every control
  tick that saw **zero** audio callbacks and clears it on the next one that saw
  any, so it is a *device-stall gauge*. Phi drives that tick every 16 ms — faster
  than the callback period at buffers of ~768 frames and up — so a perfectly
  healthy device pushed it to `1` about once a second and the chip flickered.
  A pure-Dart `AudioStallTracker` (`lib/engine/state/`) now interprets it: a run
  only counts once it covers **twice the device's callback period**
  (`ceil(2 · bufferSize / sampleRate / tick)`, floored at 3 ticks so plain timer
  jitter at small buffers can't trip it), and it counts **stall events** — latched
  on the `quiet → stalled` edge — cumulatively over the session, mirroring the
  engine's own `Demo22_MissedCallbacks` harness (transitions + peak). The gateway
  getter is renamed `deviceStallTicks` with the real semantics documented,
  `EngineTelemetry` carries `audioStalls` / `deviceStallTicks` / `peakStallTicks`,
  and `PhiEngine` exposes the same three (the tracker resets on every `start`, so
  the count is session-scoped). Covered by `AudioStallTracker` unit tests
  (threshold derivation per buffer/rate/tick, isolated blips ignored, a sustained
  run counted once, recovery re-arming, device swap re-deriving), `PhiEngine`
  telemetry tests, a `BottomStatus` widget test, and an end-to-end
  `drops_indicator` integration test (the real app: an idle flicker leaves the chip
  at `0`, a genuine stall counts once and stays once).
- **Object parameters on the node body + discoverable editing** (issue #356,
  patcher epic) — an object's arguments were invisible: a drag-created engine
  object rendered an **empty** body, and the only way to see or change its params
  was knowing to double-click. Four legs. (1) A **default args body**
  (`lib/surfaces/patcher/nodes/patch_args_body.dart`) — every node with no
  hand-authored GUI body now prints `type args` the way a Max object box does
  (`~sine 440`, `.metro 250`), read from `argsOf` on each build so it follows an
  apply and its undo/redo through the existing `markParamsChanged` wake-up.
  (2) The **reference panel shows current values**: with a canvas node selected
  the surface passes its live argument string to `PatchReferencePanel`, which
  renders `= <value>` beside each documented `PatchParamDescriptor` (positional,
  split by the shared `splitPatchArgs` in `lib/domain/patcher/patch_args.dart`,
  also used by the dialog); the panel is bound to the graph, so selection alone
  answers "what is this set to" and keeps answering it across an edit. A param
  the node carries no argument for shows no value rather than claiming the
  documented default. (3) A **node context menu** — `edit parameters…` (gated to
  the same non-GUI/has-params rule the double-click uses) · duplicate · delete,
  styled like the state canvas's menus. The secondary button is read from the
  canvas's own raw `Listener` (a `GestureDetector` there would re-enter the arena
  issue #352 emptied): it selects the node it landed on unless that node is
  already inside a multi-selection, and never counts towards a double-click.
  (4) **Port topology follows the arguments** — an object's arity is decided by
  its creation args, so `setNodeParams` now re-`inspect`s the native object and
  `PatchNode.reshapePorts` swaps in the new ports (growing the box to seat them);
  cables left hanging off a removed port are dropped from the mirror *and* the
  native patcher, returned to `SetPatchParamsCommand`, and re-wired on undo, so
  the edit round-trips without costing a connection. Covered by controller unit
  tests (grow / shrink-with-cable-drop-and-undo / unchanged-topology no-op),
  widget tests (the args body's render + refresh + hand-authored-body precedence,
  the panel's current values, right-click selection semantics, the canvas
  redrawing port dots after a reshape, the menu reaching the dialog and
  duplicating/deleting), and an end-to-end `patcher_node_params` integration test
  (drop `.metro` → body reads `.metro 250` → right-click → `edit parameters…` →
  apply 500 → body *and* panel follow → Ctrl+Z/Y round-trip both).
- **GUI bodies follow the engine** (issue #357, patcher epic) — the live bodies
  only ever re-read `guiValue` *after their own push*, so a value arriving over
  a **cable** moved the native object and repainted nothing: the seeded
  `slider → ~sine` patch is exactly that shape, and driving it from a script or
  a second editor left the canvas showing stale numbers. The Dart side gets no
  change notification from yse, so the fix is a **gated poll**.
  `PatcherController.refreshGuiValues` re-reads the display value of every node
  whose registered body renders one and raises the new
  `PatchNode.markGuiValueChanged` — the same per-node notify path
  `markParamsChanged` uses — for the ones whose value actually changed, so an
  idle patch does no repaint work however long the poll runs. A new
  `NodeDescriptor.readsGuiValue` marks the pollable set (`.slider` · `.t` ·
  `.i`/`.f` · `~sine`); it is deliberately *not* `interactiveBody`, whose set
  only overlaps — `~sine` displays a value but owns no gesture, `.b` and `.m`
  own gestures but display nothing that can change from underneath. A new
  `PatchGuiPoller` (`lib/surfaces/patcher/`) wraps the canvas and runs the ask at
  30 Hz behind three gates: the surface is the **visible tab** (the shell now
  hands `active` down to `PatcherSurface`, the milder cousin of the Scene
  renderer's park — Patcher stays mounted offstage so its canvas state survives),
  a patch is **open**, and the patch **holds a pollable node** (re-checked on
  every graph change, so the timer starts with the first live body dropped and
  stops with the last one deleted). Bodies subscribe through a shared
  `GuiValueLink` (`lib/surfaces/patcher/nodes/`) that filters the node's other
  notifications by `guiRevision`, and each decides what to do while the user has
  hold of it: a slider ignores inbound values from the first `onChanged` to the
  new `PhiFader.onChangeEnd` and re-reads once on release, a focused number box
  keeps what is being typed. Covered by controller unit tests (a cable-driven
  value wakes exactly the node it landed on, an unchanged value wakes nothing,
  non-pollable and unregistered types are never read, the gate follows the
  graph), widget tests for the bodies (thumb / toggle / number box / rendered
  `~sine` all follow; a held thumb and a half-typed field are not clobbered),
  `PatchGuiPoller` gate tests (counting the asks: offstage polls nothing, the
  poll starts and stops with the tab and with the first/last live body, an
  unmounted poller leaves no timer), and an end-to-end
  `patcher_live_value_refresh` integration test (drive the seeded objects from
  the gateway → the canvas follows → park the Patcher behind Mix → it goes quiet
  → bring it back → it catches up).
- **Inline object creation** (issue #358, patcher epic) — dragging from the
  palette was the only way to make an object, which mid-performance means
  menu-diving. The Max speed path now sits beside it: **double-click empty
  canvas → an object box appears there → type the name (+ args) → Enter**. The
  double-click reuses the canvas's own raw-pointer pairing (issue #352) rather
  than putting a recogniser back into the arena that issue emptied; an
  empty-canvas pair has no node identity to match on, so it pairs by proximity
  (`kDoubleTapSlop`, measured in **viewport** pixels — the only space whose
  meaning survives a zoom) and is invalidated by anything that is not half of a
  click: a marquee, a pan, a cable drag, a cable click, a cancelled press.
  `PatchInlineObjectBox` (`lib/surfaces/patcher/create/`) completes against
  `PatcherController.objectTypes()` — the palette's own source — matching the
  type id, the id *without* its `~`/`.` prefix (so `sine` reaches `~sine`) and
  the one-line description, prefix hits ranked ahead of substring ones; arrows
  move the highlight, Tab inserts it, and Enter instantiates the typed name when
  it is already an exact id, the highlight when it isn't. Everything after the
  first token is the creation-arg string, checked by a new pure
  `PatchCreationArgs` (`lib/engine/bridge/`) against the type's documented
  `PatchParamDescriptor`s *before* anything is minted — the engine crashes on
  arguments an object never declared (`.slider`) and is silently misconfigured by
  an out-of-range one — with the untyped tail resolved from the documented
  defaults so arguments stay positional. A refusal keeps the box open with the
  reason under it, so a typo costs a keystroke rather than the gesture; Escape
  (or a press elsewhere) dismisses and leaves the canvas untouched. Keys are
  owned by the box, between its field and the canvas, so they beat both the
  canvas shortcuts (which since issue #353 bail without primary focus) and
  Flutter's text-editing and traversal defaults — and the box takes the keyboard
  **explicitly** on open, since the canvas grabs focus on the very release that
  opens it and an `autofocus` is skipped whenever its scope already has a focused
  child. Creation also became **undoable**: it was the one canvas verb still off
  the stack, which a gesture that mints objects a keystroke at a time makes
  impossible to live with. A new `CreatePatchObjectCommand`
  (`lib/engine/state/patcher_commands/`) journals it — `addObject` stays the
  direct primitive, `createObject` is the authoring gesture both the palette drop
  and the box now come through, and a redo restores the object under its **same
  logical id** so cables and lower undo commands that named it stay valid.
  Covered by `PatchCreationArgs` unit tests, controller create/undo/redo tests,
  box widget tests (completion, keys, refusals, one Enter = one object), canvas
  widget tests (which clicks pair and which never do, where the box lands, that
  it opens holding the keyboard, Escape / click-away, Ctrl+Z), and an end-to-end
  `patcher_inline_create` integration test that makes an object by keyboard
  alone, corrects a typo in place, and undoes the result.
- **Patcher canvas interaction polish** (issue #359, patcher epic #217, design
  `docs/design/patcher.md` §6–7): the three gaps that made the canvas feel
  unlearnable next to Max, all riding the existing raw-pointer pipeline rather
  than new recognisers. (1) **Cursors and hover** — one `MouseRegion` over the
  whole viewport, fed by the *same* scene-space hit-tests the presses use, so
  what the cursor promises and what a press does cannot drift: move over
  draggable node chrome, crosshair plus a hover ring over a port (8px dots that
  previously advertised nothing), pointer over a cable, grab where one would
  detach. Committed only when the resolved target *changes*, so a pointer
  crossing empty canvas rebuilds nothing. (2) **Cables from either end** — a
  press on an inlet drags backwards and the compatible **outlets** light up;
  a press just off a port along an existing cable arms a **re-route**, detaching
  once the pointer clears the click slop (so a click near an endpoint still
  selects the cable). Every outcome is one journaled step: a new
  `RerouteCableCommand` (`lib/engine/state/patcher_commands/`) for a drop on
  another port, a plain cable delete for a drop on nothing, and nothing at all
  for a refusal or a cancel — `abortCableReroute` joins the `_resetGesture` path
  from #355 so a torn-away pointer can never make a cable vanish. (3) **Number
  scrub** — a vertical drag on a `.i`/`.f` readout carries its value (Shift
  scrubs finer, re-anchoring on the gear change so nothing jumps), read from a
  raw `Listener` so a press that never travels is still the field's click-to-edit
  from #353; the poll from #357 declines to clobber a value under the pointer,
  and the field gives up drag-to-select-text (which reports
  `SelectionChangedCause.drag` and would ask for the keyboard back on every
  scrub). Covered by canvas widget tests (cursor per zone via the mouse tracker,
  hover ring appearing and leaving, backwards connect + reject, re-route with a
  single undo, drop-on-nothing delete, click-near-end still selects, port dot
  still starts a new cable, cancelled re-route restores), number-body widget
  tests (coarse/fine/int steps, click still takes the caret, scrub leaves edit
  mode, a value arriving mid-scrub is declined), and an end-to-end
  `patcher_canvas_polish` integration test through the real app. Deferred to
  focused follow-ups: keyboard nudge, space-hold panning, and grid snap on drop.
- Unit + widget + integration tests; CI on GitHub Actions; SonarCloud
  workflow (waiting on SONAR_TOKEN)

## Surfaces

| Surface  | Status   | Folder                          |
|----------|----------|---------------------------------|
| Scene    | picking  | `lib/surfaces/scene/`           |
| Patcher  | editor   | `lib/surfaces/patcher/`         |
| Code     | scaffold | `lib/surfaces/code/`            |
| State    | scaffold | `lib/surfaces/state/`           |
| MIDI     | editor   | `lib/surfaces/midi/`            |
| Racks    | shell    | `lib/surfaces/racks/`           |
| Mix      | impl     | `lib/surfaces/mix/`             |

## Where things live

- **Design source-of-truth:** `design system/colors_and_type.css` — the
  Dart tokens under `lib/design/tokens/` are derived. Hand-maintained for now.
- **The `phi` live-coding library:** `python/phi/` — pure Python source shipped
  in the repo (issue #230, design `docs/design/live-coding.md` §3), with its
  `unittest` suite + fake `yse` bus under `python/tests/`. Not Dart, not under
  `lib/`; run inside `flutter test` via `test/engine/python/phi_library_test.dart`.
- **Design previews:** `design system/preview/*.html` and
  `design system/ui_kits/phi-workstation/*.jsx` — open these when sketching
  new surfaces in Flutter.
- **CI:** `.github/workflows/ci.yaml` (analyze + test + coverage),
  `.github/workflows/sonar.yaml` (SonarCloud).
- **SonarCloud:** project key `yvanvds_phi`, organization `yvanvds`.
- **Issue templates:** `.github/ISSUE_TEMPLATE/`. Labels: see
  [CLAUDE.md](../CLAUDE.md).
- **Architecture decision records:** this `docs/` folder —
  [timing-architecture.md](timing-architecture.md) (engine-owned clock &
  dispatch, domain clocks, playable tempo).

## How to start work on something

1. Read this file.
2. Read or update the relevant GitHub issue.
3. Branch from `main` as `<issue-number>-<short-slug>`.
4. Tests first where sensible (pure logic, FFI bridge code, end-to-end).
5. Open a PR; merge once CI + SonarCloud are green.
6. If this PR changed the architecture, layout, or stack, update this file.
