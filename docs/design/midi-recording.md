# MIDI Recording — play it in, keep it raw

> Detail doc #10 of [phase2-direction.md](../phase2-direction.md) §4.10.
> Design record, 2026-07-19 — reviewed; decisions in §8. Leads to the
> "midi recording" epic on `yvanvds/phi`. Supersedes the direction doc's
> §4.10 wording: this area is **recording MIDI-in into the piano
> roll** — audio performance capture is not this area (the direction
> doc is amended alongside this doc).
>
> **Depends on:** parsed MIDI-in + armed-voice audition (racks design,
> epic #203 — #207/#211), clip sessions + editor transport row
> (midi-clips design, epic #183 — #186/#190), and `MidiNote.voice`
> (#205). References are to reviewed designs. **No engine work.**

## 1. The problem

The piano roll can be clicked and step-entered, but the fastest way to
get a musical idea into a clip — *playing it* — doesn't exist. The
racks design brings parsed MIDI-in and an armed voice you can hear;
what's missing is capture: turning what you play into source notes of
the edited clip, on the clip's own clock.

## 2. Capture model

- **Record raw, interpret later.** Recorded notes land in the *source*
  clip exactly as played — no input quantise, ever. Interpretation is
  the transform chain's job (`QuantizationTransform`'s gravity snap
  already exists for exactly this). This is §3.7 of the vision applied
  to input: the clip is source material; the chain decides how it
  sounds.
- **Timing** comes from the session's engine clock: each note-on/off
  is stamped with the transport's `beatPosition` at arrival. Arrival
  rides the UI isolate, so precision is on the order of a frame —
  honest v1 (open question 4); if it ever pinches, engine-side input
  timestamping is a well-scoped future yse enhancement, transparent to
  this design.
- **Note assembly:** on/off pairs become `MidiNote`s (velocity kept,
  pitch as played — whole-number fractional pitch). Notes still held
  at stop are closed at the stop beat; notes crossing the loop wrap
  are closed at the wrap and continue as a new note if still held.
- **Voice:** recorded notes carry the **armed voice** — what you heard
  while playing is what's stored — and remain re-routable by the chain
  like any source note.

## 3. Recording flow

- A **record arm** button joins the editor transport row (midi-clips
  #190): arm + play starts capture; arming *while* playing punches in
  live; stop (or disarm) ends the take.
- **Loop passes overdub:** with loop on, each pass layers into the
  clip. Every pass is **one undoable command batch** — Ctrl+Z removes
  the last pass, pressed again the pass before it. A take you hate
  costs one keystroke, a take you love costs nothing.
- **Auto-extend interplay:** with auto-extend on (midi-clips #190,
  default), playing past the end grows the clip; with it off, the
  loop wraps and overdubs.
- Recording state is performance state — journal entries are the
  *note commands* (authored content, exactly like drawn notes), the
  arm itself is never persisted.
- Monitoring is the racks audition path — you hear the armed voice
  with no extra plumbing.

## 4. Metronome

The click exists to record against; no engine work:

- A **click session** — an internal one-bar click pattern looping on a
  **chosen time domain's clock** (toolbar popover: domain picker,
  beats-per-bar with downbeat accent). Bend the domain's tempo and the
  click bends with it — the metronome is polytemporal like everything
  else.
- The click plays a reserved, seeded **click voice** (synthesized from
  the sine kind — zero assets), routed to master like any voice.
- Toolbar toggle + volume; click state is performance state
  (journal-free, never persisted).

## 5. Count-in

Closes the deferral from the midi-clips design: **count-in N bars**
(0 / 1 / 2, toolbar setting) delays play — and record — while the
click counts on the session's own domain clock; capture begins on the
downbeat. Scheduled Dart-side against the engine clock query.

## 6. Panic

One permanent, unmissable action (status-bar button + palette command
+ shortcut via the shell command registry, epic #249):

1. Stop every playing clip session (transports stop, rewind); any
   armed recording ends (its notes keep — they are authored content).
2. `allNotesOff` — the MIDI output port and every materialised synth.
3. Clear pending scene spawns.
4. The click stops.

Idempotent, safe to mash. No engine work; every call exists.

## 7. Out of scope

- **Audio performance capture / bounce / export render** — explicitly
  not this area (the direction doc is amended); if it returns, it is
  its own future design with its own engine work.
- **MPE / CC / pitch-bend capture** — v1 records notes + velocity;
  controller-stream capture is a later slice (the parsed-input seam
  already carries what it needs).
- **Take management** (comping, take lanes) — overdub + per-pass undo
  is the v1 model.
- **Headphone-only click** — needs per-output routing; deferred with
  the mix design.

## 8. Review decisions (2026-07-19)

1. **Record raw, always** — no input-quantise option; interpretation
   strictly via the chain (the interpreted-not-played stance).
2. **Overdub-only v1** with per-pass undo; no replace mode.
3. **Recorded notes carry the armed voice** — what you heard is what's
   stored.
4. **UI-arrival timestamping accepted for v1** — engine-side input
   timestamps are a future yse enhancement only if it pinches.

## 9. Proposed epic breakdown

Roughly five issues, in dependency order:

1. Capture domain: the take recorder — on/off pairing against beat
   positions, stop/loop-wrap note closing, per-pass command batches,
   armed-voice tagging (pure Dart, TDD against fake input + clock).
2. Record arm + flow: transport-row button, punch-in, overdub passes,
   auto-extend interplay, per-pass undo — wired into the edited
   session.
3. Metronome: click session on a chosen domain (picker, meter,
   accent), seeded click voice, toolbar toggle + volume.
4. Count-in: N-bar delayed play/record against the engine clock —
   closes the midi-clips deferral.
5. Panic: the four-step action, status-bar button + command +
   shortcut, idempotency tests. Includes the direction-doc §4.10
   amendment landing with this epic's docs PR.
