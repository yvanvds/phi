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
    version, resolved `YSE_DLL_PATH`, active device + host, drop counter — with a
    copy button that writes a paste-ready block. Fed by `PhiEngine.engineVersion` /
    `engineLibraryPath` / `missedCallbacks` (new `YseGateway` getters).

  Covered by unit (`AppSettings`/`MidiSettings` copy-withs, `EngineMidiController`
  output-port-by-name re-resolution), widget (each section's apply/persist + the
  dialog shell), and end-to-end `settings_dialog_audio` + `settings_dialog_sections`
  integration tests (open from the File menu → drive each section → persisted).
- Mix surface: horizontal rack of `ChannelStrip` widgets (master pinned
  right, user strips left). Header has a `+` to add channels and the
  `System.audioTest` toggle. Each strip carries voice-swatch + name + fader
  with overlaid peak meter + mute/solo buttons. A user strip's header name is
  inline-editable and carries a `×` remove control (issue #141) — the master
  strip has neither.
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
  `ConditionalMutingTransform` (drops notes matching a declarative
  `NoteCondition` — a leaf `NoteFieldCondition` (field · comparison ·
  threshold over pitch/velocity/channel/start) or an `all`/`any`
  `NoteConditionGroup` of them; issue #109 replaced the bare `NotePredicate`
  callback with this serialisable model, keeping `NotePredicate` only as the
  evaluated keep-form, and still standing in for the future
  state-machine/scene-volume/code-variable read). The `spawn · agent @ p,v` chip is real as of issue #37:
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
  is a `ProjectManifest` (format version + name + tempo + scene name) and whose
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
- Unit + widget + integration tests; CI on GitHub Actions; SonarCloud
  workflow (waiting on SONAR_TOKEN)

## Surfaces

| Surface  | Status   | Folder                          |
|----------|----------|---------------------------------|
| Scene    | picking  | `lib/surfaces/scene/`           |
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
