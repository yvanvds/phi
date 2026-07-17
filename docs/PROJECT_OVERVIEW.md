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
  consume.
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
