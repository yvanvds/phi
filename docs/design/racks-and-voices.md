# Racks & Voices — synth definitions, playable voices, and effects

> Detail doc #5 of [phase2-direction.md](../phase2-direction.md) §4.5.
> Design record, 2026-07-19 — reviewed; decisions in §10. Leads to the
> "racks & voices" epic on `yvanvds/phi`.

## 1. The problem

The engine ships rich synthesis — an SFZ sampler, a DX7-compatible FM
engine with sysex bank import, a virtual-analog with wavetables, and a
full insert-effect roster — with **no UI at all**. Notes leave Phi only
as external MIDI. And the *voice* — the thing the registry doc named the
keystone (§10) — is still half-formed: a swatch index on mix strips and
a bare channel int on notes. Nothing binds *note → sound → bus*
together, which also blocks audition (deferred out of the midi-clips
epic) and MIDI-keyboard experimentation (an explicit direction-doc
goal).

## 2. What the engine offers (confirmed against the bridge)

- **Synths:** `Synth` instances host voice banks per note-range *and
  MIDI channel* (`addSineVoices` / `addVaVoices` / `addFmVoices` /
  `addSamplerVoices`). VA exposes the full panel (oscs, wavetables,
  filter, envelopes, LFO); FM loads `Dx7Bank.load(sysex)` with
  `patchCount`/`patchName` enumeration plus per-op tweaks; the sampler
  loads `SfzInstrument.load(path)` or a one-sample instrument via
  `SfzInstrument.fromSample`.
- **Internal dispatch has landed:** `ClipTransport.connectSynth(synth)`
  drives a synth's note events **from the audio thread, sample-
  accurately** — the timing doc's "when those land" is here. A transport
  broadcasts its events to every connected synth; synth voice banks
  filter by MIDI channel.
- **Audio routing:** `Sound.fromSynth(synth, channel: bus)` renders a
  synth into a mix bus — the voice's output binding. (A `Sound` also
  carries the 3D position and per-note `setNotePosition` — the scene
  tie-in, deliberately not this epic.)
- **Effects:** `DspObject` factories — lowpass / highpass / bandpass,
  sweep, three delays, phaser, ring modulator, difference, granulator,
  `Compressor`, and `DspObject.patcherInsert(Patcher)` (a patcher as an
  insert!). Chains via `link`; placed with `Channel.dsp` (pre-fader,
  before reverb and volume).
- **MIDI-in:** the bridge parses input messages (`MidiInParsedMessage`);
  Phi's gateway currently exposes only an activity tick — it grows a
  parsed stream here.

No blocking engine work. One deliberate constraint appears in §3.

## 3. The voice — the keystone entity

A `voice.` entity binds what a note needs, exactly as parked in the
registry doc §10:

```json
{ "kind": "internal", "synth": "synth.fm_bells",
  "output": "mix.perc", "color": "amber" }
```

- **Synth entities are definitions; voices instantiate.** `synth.` is a
  recipe (kind + params + assets). Creating a voice materialises its
  *own* engine `Synth` from the definition plus a `Sound` binding it to
  the voice's bus. Two voices may share one definition and different
  buses; editing a definition re-applies to every voice built from it.
  Re-pointing `voice.bells` at another definition swaps the sound
  behind a stable identity — the whole point.
- **External voices fold in:** `"kind": "external", "channel": 3`
  plays through the open MIDI output port instead of an internal synth.
  Today's hardware workflow becomes a voice like any other — clips and
  code never care which kind they address.
- **Channel allocation:** each internal voice gets a stable engine
  channel (1–16) allocated at creation; its synth's voice banks
  register on that channel, and a session transport connects the synths
  of every voice its output routes to. **v1 ceiling: 16 internal
  voices** (the MIDI channel space) — acceptable for a performer's
  dozen families; a per-connection channel filter in yse lifts it later
  if it ever pinches, and the allocation table makes that swap
  invisible.
- **Color** comes from the voice (shown on mix strips, library rows,
  and later wherever sound is displayed — application points stay
  experimental per the registry doc).

## 4. Synth definitions

`synth.` payloads by kind:

- **`va`** — the full panel: oscillators (wave, detune, level, pulse
  width), wavetable position, filter (cutoff, resonance, key tracking,
  env/vel amounts), amp + filter envelopes, LFO (type, rate, targets),
  gain, voice count.
- **`fm`** — a bank asset reference + patch index (+ optional
  algorithm / feedback / per-op overrides), voice count.
- **`sampler`** — an SFZ asset reference *or* a single-sample recipe
  (root, range, attack/release), voice count.
- **`sine`** — voice count only; the zero-config starter (a fresh
  project seeds `voice.default` → `synth.sine` → master).

**Assets** (`.sfz` + samples, `.syx` banks, wavetables) are copied into
the project's `assets/` folder on import and referenced by relative
path — projects stay portable, per the registry doc §5.

## 5. Effects

- An `fx.` entity is **one instance**: kind + params (e.g.
  `fx.big_delay` → lowpass delay, taps, impact). Live code addresses it
  (`fx.big_delay.impact = 0.5`).
- **Placement lives in the mix payload:** a bus's `inserts` list is an
  ordered list of `fx.` addresses, materialised as a linked
  `DspObject` chain on the engine channel. An instance sits on **at
  most one** bus — enforced through back-references (placing it
  elsewhere moves it, with the usual impact dialog).
- `patcherInsert` joins the roster when the patcher epic lands its
  registry entities; the fx kind exists from day one so nothing
  re-plumbs.
- The single global reverb (`attachReverb`) gets **no UI in v1**.

## 6. Note flow — the channel → voice migration

The contained migration the direction doc planned:

- `MidiNote.channel` (int) becomes `MidiNote.voice` (a `voice.`
  address). `VoiceRoutingTransform` rules assign voices;
  `SplittingTransform` layers carry voice refs; the default chain routes
  to the seeded voice. **No compat shim** — the established stance.
- At flatten time the session maps each routed voice to its allocated
  channel, pushes `TransportNote`s as today, and connects the
  transports: `connectSynth` for each internal voice in the output,
  `connectMidiOut` when any external voice appears.
- SMF **import** maps file channels onto voices (ch 1 → the seeded
  voice, others created as needed); **export** writes each voice's
  allocated channel.
- Ghost-note painting may now color by routed voice — still an
  *experiment to try*, not a commitment (registry doc §10).

## 7. MIDI-in and audition

- The gateway grows a **parsed input stream** (note on/off, velocity,
  channel, port) over the bridge's existing `MidiInParsedMessage` —
  replacing nothing; the settings epic's activity tick stays.
- **Arm a voice** (one at a time, in the racks surface or the mix
  strip): live input plays it immediately — the "experiment with a
  sound from a keyboard" goal. Immediate-path `noteOn`, not through a
  transport.
- **Audition unlocks in the roll:** clicking a note (and caret step
  entry) previews through the note's *routed* voice — closing the
  deferral from the midi-clips epic.

## 8. The racks surface

A new rail entry (**Racks**), three panes:

- **Left — definitions:** the `synth.` and `fx.` lists (grouped,
  ordered, the usual registry tree affordances); add-menu per kind;
  duplicate / rename / delete with impact dialogs.
- **Center — editor:** the selected definition's panel. VA: sectioned
  sliders/selects from the design system; FM: bank file picker, patch
  list (names from the bank), op grid; sampler: SFZ/sample picker +
  range fields; fx: one row per param. All edits are journaled payload
  commands, gesture-coalesced where continuous.
- **Right — voices:** one row per `voice.`: name, synth picker
  (definitions), bus picker (mix tree), color, kind toggle
  (internal/external + channel), **arm** toggle, and a one-octave
  on-screen test strip for mouse audition.

## 9. Out of scope

- **Scene ↔ voice binding and per-note spatial** (`setNotePosition`,
  `PositionHandler`) — undesigned, deliberately deferred (registry doc
  §10).
- **Reverb UI** — the single global reverb stays engine-default.
- **Wavetable authoring** (`loadVaWavetable`) — the VA plays its
  built-ins; a wavetable editor is its own later feature.
- **`VelocityToParameterTransform` → synth-param wiring** — the
  transform's `ParameterEvent` seam connects to synth params in a later
  slice; nothing here blocks it.
- **Recording MIDI-in into clips** — §4.10 with recording.

## 10. Review decisions (2026-07-19)

1. **Synth entities are definitions; voices instantiate** their own
   engine synth from the shared recipe (§3).
2. **External voices are folded into the voice model** — external MIDI
   is a voice kind, never a bare channel.
3. **Effects ship in this epic** — the engine is ready and the mix
   epic built the insert seam's home.
4. **The 16-internal-voice ceiling is accepted for v1** — a per-
   connection channel filter in yse lifts it later; the allocation
   table makes that swap invisible when it comes.
5. **Voice color extends to the full token palette** — voices are
   identity; the six-swatch set stays as quick picks.

## 11. Proposed epic breakdown

Roughly nine issues, in dependency order:

1. Domain: `voice.` / `synth.` / `fx.` entities, payload schemas per
   kind, channel-allocation table, codecs (pure Dart, TDD).
2. Domain: `MidiNote.channel` → `MidiNote.voice` migration — routing/
   splitting transforms, default chain, SMF import/export mapping, no
   compat (pure Dart, TDD).
3. Gateway: synth surface (materialise per kind from a definition
   payload, param application, dispose), `Sound.fromSynth` bus binding,
   `connectSynth`/`connectMidiOut` on transports, asset loaders.
4. Gateway: fx surface (`DspObject` per kind, param sets, linked
   chains on channels) + parsed MIDI-in stream.
5. Engine: voice materialisation + re-sync (instantiate synth+sound
   per voice, definition edits re-apply, bus re-binding), session
   transport connection by routed voices.
6. Racks surface shell: rail entry, three-pane layout, definitions
   list with registry affordances.
7. Param editors: VA / FM (bank + patch browser) / sampler panels,
   asset import into `assets/`; fx param rows.
8. Voices pane: create/bind/color/kind, arm-for-input, test strip;
   MIDI-in → armed voice; roll + step-entry audition through routed
   voices.
9. Effects placement: `inserts` list on mix strips, chain
   materialisation, move-with-impact, live-param addressing readiness.
