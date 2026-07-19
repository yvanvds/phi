# State Graph — states that do something

> Detail doc #8 of [phase2-direction.md](../phase2-direction.md) §4.8.
> Design record, 2026-07-19 — reviewed; decisions in §8. Leads to the
> "state graph" epic on `yvanvds/phi`.
>
> **Depends on:** the midi-clips sessions (epic #183) for clip play
> slices, the mix tree (epic #164) for level slices, and the
> live-coding design ([live-coding.md](live-coding.md), epic #228) for
> `state.fire` from code and on-enter script evaluation. References are
> to reviewed designs. Scope is the direction doc's *modest* cut —
> morphing transitions stay Phase ≥ 3.

## 1. The problem

The State surface authors a graph — nodes, corner-pin transitions,
arm/fire, one live state — and the live state guards MIDI-graph
branches. That is all it does. States configure nothing: the
inspector's DOMAINS · CODE BLOCKS · SCENE REF sections are empty
placeholders, transitions fire only by hand, and the graph itself is
not an entity — unnamed, unsaved, gone on restart. A performance
cannot yet be *structured*.

## 2. What exists to build on

- Pure-Dart `PerformanceState` / `StateTransition` / `StateGraph` /
  `StateSnapshot` (`lib/domain/state_machine/`), the
  `StateMachineController`, and the canvas surface (pan/zoom, pins,
  béziers, arm capsule, LIVE capsule, cross-surface selection into the
  inspector).
- The MIDI graph's `StateMatchCondition` guards evaluate against the
  live state — the one working consumer.
- `RuntimeVariableRegistry` (engine-owned, live values), clip sessions
  (#183 design), the mix tree (#164), domain tempo binding, and the
  `phi` control plane's `fire` verb (#228 design, #233).

## 3. States as entities

- **`state.` joins the registry** — one entity per state. Addressing
  stays uniform (`state.intro` in live code, in guards, in
  completion), rename-refactor covers every reference, and the
  standard affordances (groups, ordering, delete-impact) come free.
- **Transitions live in the source state's payload** — an ordered list
  of `{to, trigger, label}`. The target is an entity address, so
  rename-refactor rewrites it; delete-impact on a state lists inbound
  transitions.
- Node canvas position is a payload field (the patcher precedent:
  layout rides the entity).
- **`StateMatchCondition` migrates** from `PerformanceStateId` to the
  entity address — MIDI-graph guards then survive state renames via
  the ordinary refactor. No compat shim, per the established stance.
- The seeded fresh project keeps `intro` (live) → `verse`.

## 4. What a state does — captured slices

A state carries **explicitly captured, per-category slices** — never
an automatic whole-world snapshot. Uncaptured categories are left
untouched on entry, which is the no-hierarchy principle in practice: a
state constrains exactly what the performer told it to.

v1 slice categories:

| Slice | Captures | Applies |
|-------|----------|---------|
| **clips** | the set of playing clips (+ loop flags) | play/stop to match; other clips untouched |
| **mix** | volume/mute per chosen bus | live levels (ramped by the engine's fades) |
| **variables** | `RuntimeVariableRegistry` values | sets values → MIDI-graph branches re-route |
| **tempos** | per-domain tempo | domain clock rates |

- **Capture is a button per category** in the inspector: "capture
  clips now" stores the currently-playing set into the state; "clear"
  removes the category. What's captured is listed, readable, and
  hand-editable (remove one entry without recapturing).
- **Application is performance-rate and journal-free** (open question
  2): firing a transition changes what you *hear*, not what you
  *authored* — payloads are untouched, nothing enters the journal, and
  a crash-recovery replay lands on the authored state, not
  mid-performance. This matches clips' play-state-is-never-persisted
  rule.
- **On-enter script** (optional, per state): a `code.` entity
  reference evaluated on entry through the ordinary evaluator — the
  cheap power move that covers everything slices don't (spawn agents,
  rewire a patcher, anything the `phi` library can say). Missing
  references degrade gracefully.

Application order on entry: variables → tempos → mix → clips →
on-enter script (structure first, sound last, script over everything).

## 5. Transitions and triggers

Trigger kinds in v1 (each transition has exactly one):

- **manual** — today's arm + fire capsule, unchanged.
- **code** — `state.verse.fire()` via the `phi` control plane (#233);
  also the seam any future trigger source can use.
- **timed** — "N beats after entering the source state, on domain D":
  scheduled against the domain clock, cancelled if the state is left
  first. The first structural use of pluralistic time.
- **variable** — fires when a `RuntimeVariableRegistry` value matches
  (checked on variable change, not polled).

Arming stays meaningful for manual transitions; timed/variable/code
transitions fire without arming. The canvas badges each transition
with its trigger kind; tapping a transition opens its trigger editor
(the existing tap-to-arm gesture moves to the badge).

Audio-analysis and sensor triggers stay future work (vision §3.8) —
the trigger model is an enum they extend.

## 6. Inspector

The placeholder sections give way to the real thing:

- **Name** (inline edit → registry rename, as today).
- **SLICES** — the four categories with capture / clear / view;
  captured entries listed with per-entry remove.
- **ON ENTER** — `code.` entity picker (or none).
- **TRANSITIONS** — outbound list: target, trigger kind + params,
  label; add / remove / edit here as well as on the canvas.

## 7. Out of scope

- **Morphing / interpolated transitions** (vision §3.8) — Phase ≥ 3;
  the trigger model and slice application are designed so a morph can
  later wrap them (a morph is an application spread over time).
- **Scene slices** (agent poses, effect volumes) — waits for the scene
  wave; the slice table is an enum that extends.
- **Voice/synth rebinding slices** — racks territory; add a slice
  category when a real need appears, not speculatively.
- **Probabilistic / conditional-expression triggers** — later; the
  variable trigger covers the common case.
- **State entry/exit *actions* beyond slices + script** — the script
  *is* the action escape hatch.

## 8. Review decisions (2026-07-19)

1. **States are `state.` entities**, transitions in the source state's
   payload — uniform addressing, refactor coverage, free affordances.
2. **Application is journal-free** — firing a state is performance,
   not authorship; recovery replays land on the authored state.
3. **The full trigger set ships in v1:** manual + code + timed +
   variable.
4. **The on-enter script ships in v1** — the cheap power move.

## 9. Proposed epic breakdown

Roughly seven issues, in dependency order:

1. Domain: `state.` entities (payload: position, transitions,
   slices, on-enter ref), codec, seed migration, `StateMatchCondition`
   → entity addresses (no compat), back-references (targets, code
   refs, slice refs) — pure domain, TDD.
2. Registry-backed controller: `StateMachineController` reads/writes
   entities; canvas renders from the registry; arm/fire and the LIVE
   capsule keyed by address; guards re-route on rename.
3. Slice model + capture: the four categories, capture-from-live,
   per-entry editing, payload round-trip.
4. Application engine: ordered journal-free application through the
   owning controllers (variables → tempos → mix → clips → script),
   graceful missing-reference handling.
5. Triggers: model + editors (manual arm as today, timed on domain
   clocks with cancellation, variable-match on change, code via the
   `phi` seam), canvas badges.
6. Inspector: SLICES / ON ENTER / TRANSITIONS panels replacing the
   placeholders.
7. End-to-end + live-code wiring: `state.` in the registry mirror,
   `state.current`, fire-from-code, an integration test walking a
   two-state performance (capture, fire, timed follow-on, variable
   branch re-route).
