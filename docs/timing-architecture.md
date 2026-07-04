# Timing Architecture — clock in the engine, interpretation in Dart

> Decision record, 2026-07-04 (issue #99). This documents *target*
> architecture agreed after diagnosing unsteady MIDI playback; the code
> migrates toward it across several epics. Where
> [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) describes the current
> Dart-side player, that is scaffolding this document supersedes.

## 1. The problem

MIDI playback is currently dispatched from the Flutter UI isolate:
`EngineMidiController` runs a `Timer.periodic(16ms)` and fires
`noteOn`/`noteOff` through FFI on each tick. A Dart timer is serviced by
the same event loop that handles widget rebuilds, gestures, and the 3D
viewport. Interacting with the scene or the transform graph delays the
timer, and notes come out bunched or late. YSE's audio threads are
stable — but they sit *downstream* of an unstable clock; they never see
a note until the UI thread has already decided when to send it.

This contradicts the vision ([phi-vision.md](phi-vision.md) §5): *"All
time-critical work happens here [the engine]."* The Dart player was
expedient scaffolding, not the destination.

## 2. The decision, in one line

**The engine owns the clock and the dispatch; Dart owns the
interpretation.** No note is ever dispatched from the UI thread.

This is the split every serious DAW uses: the UI edits a data model and
hands immutable snapshots to the audio thread; the audio callback is the
timing authority that decides *when* events fire.

### What moves into YSE

- A **clip transport**: accepts a flat list of timed note events
  (start, duration, channel, pitch, velocity — in *beats*), a loop
  length, and a binding to a **domain clock**. Plays it from the audio
  callback, looping.
- **Domain clocks**: one beat accumulator per time domain, advanced
  each audio block by `blockSeconds × tempo/60`. All clocks derive from
  the single sample clock (the audio callback) — never independent
  timers — so polytemporal relationships (ratios, drift, convergence)
  stay exact and deterministic.
- **Event dispatch**: per audio block, each playing transport converts
  the block boundaries into a beat window on its clock and fires the
  events that fall inside it — to external MIDI now, to internal synths
  (sample-accurately) when those land. Nothing is ever scheduled ahead
  in absolute time; events are *evaluated*, not *booked*, so tempo
  changes never require rescheduling.
- **Note-off bookkeeping** (the `_sounding` set) and pitch-bend
  emission for microtonal playback move with the dispatch.

### What stays in Dart

- The whole interpretation layer: `MidiTransformChain`, the transform
  graph, state-guarded branches, live-coded custom transforms, editing.
  This is Phi's soul and stays malleable.
- The push contract: the chain/graph output is already memoised and
  revision-keyed (issue #56). Instead of "read the output every 16 ms
  and dispatch", the contract becomes **"whenever the revision bumps,
  push the new flattened note list to the engine transport"**. The
  engine swaps event buffers at the next block boundary.
- "Interpreted, not played" (§3.7) survives intact — an edit or a state
  flip re-evaluates once in Dart, pushes, and is heard within one audio
  block, with *better* immediacy than today because UI jank is no
  longer in the path.

## 3. Tempo is played, not set

Domain tempo is a **control signal**, not a setting — the same species
of thing as a filter cutoff. This is the "time is pluralistic" principle
(§2 of the vision) taken seriously: a DAW built to escape the grid must
not hard-code its tempos.

- **Engine primitive**: `setTempo(domain, target, rampSeconds)` —
  deliberately dumb, idiomatic YSE (its numeric setters already take a
  `fade`). Beat position is the running integral of tempo, accumulated
  per block; notes fire on their beat crossings no matter how the rate
  moves underneath.
- **Expressiveness lives in Dart**: tempo curves, "accelerate over four
  bars", LFO-on-time, a fader riding a domain — all are Dart-side
  steering of that one primitive. Tempo *functions* never cross the FFI
  boundary.
- **Sources compose**: a domain's tempo input is a list of sources
  summed Dart-side at control rate, even if the list almost always has
  one entry. Idle cost is zero (no ticker, no FFI calls when nothing
  modulates); engine-side cost is unchanged regardless of stacking.
- **Control-rate steering from Dart is safe** precisely because of the
  split above: a janky frame delays a tempo nudge by ~30 ms → the
  engine integrates the old tempo slightly longer and the ramp catches
  up. A late note is a glitch; a late tempo nudge is inaudible.
- **Convergence is a layered feature**: played tempo trades away
  guaranteed alignment (the Nancarrow/Grisey precomputed-curve trick).
  When planned reconvergence is wanted, an "autopilot" takes over a
  domain's tempo and steers it toward the meeting point — built on top
  of the same primitive, like autopilot over manual controls.

## 4. Consequences for existing code

- **`DomainSubscriptionTransform` inverts.** It currently bakes tempo
  into the note data (rescales start/duration by
  `referenceTempo/domainTempo` at evaluation time). In the engine-clock
  world the clip stays in domain-beats and the *transport's choice of
  clock* expresses the subscription. Tempo belongs in the clock, not in
  the notes — otherwise every live tempo change forces a re-evaluate +
  re-push, sneaking the rescheduling problem back in through the data.
- **Scene spawning re-anchors.** Agent spawn/despawn currently rides
  the note dispatch on the UI tick. With an engine transport, the UI
  queries the engine playhead at frame rate and derives spawns from the
  same clip data. Visuals need frame accuracy only.
- **Playhead display** likewise becomes a frame-rate query of the
  engine clock, not a Dart-side accumulator.
- **Event model starts minimal**: notes + pitch bends (microtonal).
  Parameter events (`VelocityToParameterTransform`) ride the same
  sample-accurate stream as a second slice.

## 5. Rejected alternatives

- **Background Dart isolate for the player.** Dodges UI jank without
  touching C++, but Dart timers still jitter at millisecond level,
  Windows timer resolution is coarse, FFI-from-another-isolate raises
  RtMidi thread-safety questions, and the work is discarded once the
  real transport lands. Not worth the detour.
- **Absolute-time event scheduling** (a master schedule in seconds).
  Dead on arrival for polytemporal music: every tempo change
  invalidates every future event; ramped tempo degenerates into
  rescheduling every block.
- **Independent per-domain timers/threads.** Domains would accumulate
  drift against each other; "reconverge at bar 17" becomes approximate.
  Independent *clocks*, yes — independent *timing sources*, no.
- **Moving the transform chain/graph into C++.** The interpretation
  layer is control-rate work and Phi's most malleable surface; it gains
  nothing from the audio thread and loses hot-reload, live coding, and
  testability.

## 6. Scope notes

- Domain clocks here cover the **metric** kind first. The vision's
  other domain kinds (§3.4 — phase-based, event-driven, continuous,
  external) should map onto the same accumulator model but are not
  designed yet.
- The vision's broader "engine owns the Scene" (§5) is a larger
  migration (the Dart `SceneField` etc.); this document scopes only
  timing and MIDI dispatch. The same clock/interpretation split should
  inform that later work.

## 7. Implementation trail

- Engine capability: transport + domain clocks + rampable tempo →
  issue on `yvanvds/yse-soundengine`.
- Bridge surface: wrap transport/clock/tempo API → issue on
  `yvanvds/dart-yse`.
- Phi migration epic: push contract, subscription-as-clock-binding,
  scene re-anchoring, playhead query → epic on `yvanvds/phi`.
