# Phi

*A flexible workstation for live electronic music performance.*

---

## 1. Motivation

The tools that exist for live electronic music all reflect a particular way of thinking, and none of them fit how I want to work.

Linear DAWs (Reaper, Logic, Pro Tools) assume a timeline with a master clock. They are good for studio production and bad for performances where the path through the music is not predetermined. Ableton Live softens this with its session view, but the unit of flexibility is still the premade clip. A clip is a block of audio or MIDI; it is not a piece of behavior. Live's model assumes that every instrument shares the same tempo and meter, which is wrong for the kind of polytemporal music I am increasingly interested in.

Max/MSP and Pure Data give me patcher-style programming, which is the right surface for some kinds of thinking — signal flow, modulation networks, generative systems. But patchers are awkward for structural composition, and they assume a single time base. SuperCollider, TidalCycles, Sonic Pi and other live-coding systems give me the opposite: tight pattern grammar, but no spatial intuition and no good story for combining written-in-advance material with improvisation.

I have built my own audio engine (yse-soundengine) that combines DSP with a 3D scene model. The 3D part is not for visual spectacle. It is for thinking about sound spatially and behaviorally — sounds that move, attract, repel, cluster, fly. That model already does something the existing tools do not, but it is currently just an engine. It needs a workstation around it.

Phi is that workstation. It is the next step for the kind of music I want to make.

The artistic motivation is hard to articulate ahead of the tool, because I expect the tool to suggest things to me as I use it. That is, in a sense, the point. Existing tools constrain my thinking to their shape; Phi should be open enough that new ideas surface from playing with it. **Flexibility, not rigidity, is the central design value.**

## 2. Guiding Principles

These principles are the design stance. Everything else in the document follows from them.

**No hierarchy of authority.** Phi has no master clock, no master sequencer, no privileged layer that the others must obey. Any component can influence any other, subject only to technical feasibility. A 3D action can modulate a DSP patch. Live code can transform a MIDI stream. A state transition can rewire signal flow. The performer decides what influences what, and rewires those relationships at will. This is the structural commitment that makes everything else possible.

**Time is pluralistic.** There is no global tempo. Time domains are first-class objects that the performer creates, modifies, and destroys during performance. Different parts of the music can run on different clocks, drift, gravitate toward each other, lock and unlock. Linear time is one possible mode, not the default.

**3D space is semantic, not decorative.** Position, proximity, velocity, occlusion, and selection in the 3D scene have musical meaning. The scene is not a visualization of music made elsewhere; it is one of the surfaces on which music is made.

**Performative over compositional.** The default mode is creating, modifying, and destroying things during performance, not before it. Preparation is supported, but the system is biased toward live manipulation. The state machine and clip systems exist to give performances *structure*, not to lock them down.

**Multiple surfaces over one model.** The performer can manipulate the system through patcher diagrams, live code, direct 3D manipulation, MIDI clips, or a state graph. These are not separate worlds. They are different views and different idioms over the same underlying scene. What is grabbed with the mouse in 3D can be named in code. What is written in code can appear as an object in space.

**Audience legibility matters.** A performance is for an audience. The visual surface of the tool — what is projected during a show — should communicate what is happening, both as a visual artefact in its own right and as a window into the music's structure. This shapes the visual design and the live-coding language.

## 3. Conceptual Architecture

Phi is organized in layers, but the layering is conceptual rather than enforced. Every layer can influence every other.

### 3.1 The Scene

The Scene is the central data structure. Everything is in it: sound-producing agents, DSP graphs, MIDI clips, time domains, code blocks, state definitions, selections, regions, attractors. The Scene exists in a 3D coordinate space, though many of its inhabitants do not have meaningful positions and live "outside" it.

The Scene is the thing that gets saved when a performance is saved, the thing the audience sees a window into, the thing the performer queries and mutates. All other surfaces (patcher, code editor, state graph, MIDI editor) are views and editors over the Scene.

### 3.2 Sound Sources and DSP

The audio engine renders sound. It hosts DSP graphs — synthesizers, processors, effects — built either visually in the patcher or programmatically. DSP graphs can be connected to each other, to MIDI streams, to scene parameters (a swarm's cohesion controls a filter cutoff), to time domains.

DSP is the lowest-latency, most constrained layer. Modifications to a running DSP graph must respect realtime audio. This is the one place where "no hierarchy" runs into technical reality: audio runs on its own thread, and not every cross-layer influence can happen at audio rate. Cross-layer modulation operates at control rate by default; audio-rate connections require explicit setup.

### 3.3 The Spatial Layer

The 3D scene contains agents — entities with position, velocity, and a sound. Agents can be individual (a single sound at a point) or part of swarms (populations with emergent behavior: cohesion, alignment, separation, target attraction, individual variance).

Spatial relationships have musical consequences. Proximity can drive modulation depth. A volume in space can act as an effects send. Line-of-sight or occlusion can shape signal flow. Velocity can map to excitation or trigger density. These mappings are configurable per agent or per group; they are not hardcoded.

The performer interacts with the spatial layer directly: grabbing agents, lassoing groups, painting trajectories, placing attractors, dropping field volumes. Direct manipulation is one input mode among several; code can do everything direct manipulation can.

Visualization is part of the spatial layer's job. Agents have visual identity that should track their sonic identity. The look is gritty and minimal — primitives, particles, glow and blur effects, dark backgrounds, emissive colors. The aesthetic is closer to signal-processing visualization than to game graphics.

### 3.4 Time Domains

A time domain is a source of "now" — anything that produces a notion of when events happen. Domains can be:

- **metric** (a tempo and meter)
- **phase-based** (a cycle of length N without inherent beat)
- **event-driven** (advances when something happens)
- **continuous** (a rate, no ticks — useful for sweeps and slow morphs)
- **external** (synchronized to MIDI clock, Ableton Link, or audio analysis)

Domains do not own objects. Objects subscribe to domains, and an object can subscribe to multiple domains with weights, blending their influence. Subscriptions change at runtime — through code, through state transitions, or through spatial proximity to a domain's region in 3D space.

Domains themselves can relate to each other: independent, ratio-locked, phase-locked, derived. These relationships are themselves modulatable.

Crucially, freeform time (no clock at all) is just another domain — the one where events fire when triggered. This keeps the architecture uniform: there is no special case for "untimed" material.

The performer creates, modifies, and destroys domains during performance. Domains can be visualized as regions or attractors in the 3D scene; pulling a sound into a region's gravity well subscribes it to that domain.

### 3.5 The Patcher

A node-and-cable surface for building DSP graphs, modulation networks, event-processing chains, and signal routing. The patcher is for the kind of thinking that benefits from spatial layout — what is connected to what, who modulates whom.

The patcher is not separate from the rest of the system. Patches live in the Scene. A patch can be parameterized by a swarm's behavior or by a code variable; a patch can emit events that drive other parts of the system. The patcher is one editor among several, not a closed world.

### 3.6 Live Coding

A live-coding surface where the performer writes, evaluates, and re-evaluates Python code during performance. Python is the host language — chosen because it is familiar, AZERTY-friendly, and well-supported, not because a new language was needed.

On top of Python sits a domain-specific vocabulary: a library of verbs, objects, and named parameters tuned for music and performance. The vocabulary is designed for legibility — verb-first commands, named arguments, words from music rather than from computer science. The goal is that code projected on a screen during a show is *somewhat* readable to a non-programmer in the audience.

Code is a first-class surface for manipulating the Scene. Anything that can be done with the mouse can be done in code, and vice versa. Code can create agents, modify domains, redefine swarm behaviors, transform MIDI streams, trigger state transitions. Code blocks can themselves be placed in the Scene — they can have positions, subscribe to domains, operate within volumes — making spatial scoping of code an option.

Two display registers exist: a *working* view (where the performer actually edits, with all the helpers and aliases muscle memory wants) and a *projected* view (where names expand, recently-changed lines highlight, noise is stripped, and the audience can follow). The same code, two renderings.

### 3.7 MIDI and Linear Material

MIDI clips are globally available in the Scene. A clip is not played; it is *interpreted*. A clip is a source of events that pass through a transformation graph before producing sound.

Transformations are categorized:

- **pitch** (scale conformance, including microtonal and fractional MIDI; transposition; inversion; spectral mapping)
- **time** (which domain the clip subscribes to; quantization gravity; humanization; probabilistic skip/repeat; stretch)
- **voicing** (which voice(s) each note routes to; velocity-to-parameter mappings; splitting across sources)
- **structural** (looping, reversing, branching, conditional muting)

Which transformations apply is context-dependent. A clip in state A is transformed one way; in state B, differently. The same notes can sound entirely different across the performance.

Clips can be rendered in 3D. A note-on can spawn an agent at a position determined by pitch, time, velocity, channel. The agent lives for the note's duration. A melody becomes a trail; a chord becomes a cluster. Once spawned, agents are subject to all the spatial machinery — they can be grabbed, scattered, attracted, sent into effect volumes. The linear and the spatial dissolve into each other.

### 3.8 The State Machine

A performance is a graph of states. Each state defines a configuration of the system: which domains exist, which agents are alive, which code is loaded, what the scene looks like, what is routed where. Transitions between states are triggered — manually, by time, by audio analysis, by sensors, by code, by any condition that can be expressed.

A linear piece is a straight-line graph. An improvisation is a graph with many edges and the performer chooses live. A piece can have recurring states, conditional transitions, probabilistic branches.

Transitions can be discrete or continuous. A morphing transition interpolates between two states over a defined duration or beat count: tempos crossfade, swarm parameters drift, code blocks fade in and out. Structure becomes a continuous unfolding, not a slideshow.

The state machine sits *on top of* the rest of the architecture. A state is not a different kind of thing; it is a snapshot of configuration. This is what allows it to coexist with everything else without imposing a hierarchy.

### 3.9 Relationships Between Layers

The crucial commitment, restated: any layer can influence any other. The Scene is the shared substrate that makes this possible. Some examples of cross-layer influence:

- a swarm's density modulates a DSP filter
- a MIDI clip's events are quantized to a domain whose tempo is set by audio analysis of a microphone input
- a state transition is triggered by an agent entering a volume
- a code block's behavior is parameterized by the position of a 3D object the performer is dragging
- a patch's output is rerouted automatically when the active state changes

Some directions of influence are technically constrained — MIDI streams cannot easily rewrite live code, for instance, because the code is the thing that processes the stream. But these constraints are practical, not philosophical. The system does not enforce hierarchy; it enables whatever the performer can construct.

## 4. The Performance Experience

This section is about what playing Phi feels like, and what an audience sees.

The performer faces multiple windows: a 3D viewport, a patcher canvas, a code editor, a state graph, a MIDI editor, mixing controls. These can be arranged across one or more displays. A controller — physical knobs, faders, buttons, a tablet — sits alongside keyboard and mouse for direct, tactile manipulation of parameters and selections.

During performance, the performer moves between surfaces fluidly. A swarm gets seeded with code, then sculpted by hand in 3D, then handed to a different time domain by dragging it into a region. A MIDI clip is loaded, scale-conformed by selecting a transformation in the patcher, and routed to spawn visible agents whose flight paths the performer perturbs in real time. A state transition fires from a controller button; the system morphs over four bars of the active domain into a new configuration.

The projected display for the audience is curated separately from the working displays. It might show the 3D scene full-screen, or a split of the scene and the live-coding view, or only the code, or only the scene. Recently-changed code highlights briefly; agents pulse with sonic activity; transitions in the state graph are visible as the performer triggers them. The audience does not see everything the performer sees, and does not need to. They see enough to understand that something is being shaped in front of them.

The aesthetic is dark, gritty, glowing. Primitives and particles. Minimal text. The visual identity of Phi is closer to an oscilloscope than to a video game.

## 5. Technology Stack

The stack is chosen to ship Phi in a reasonable time, with a polished look, on a platform that runs reliably during performance.

- **Audio engine:** C++ (existing yse-soundengine, extended). Handles DSP, the realtime audio thread, scheduling, the authoritative Scene state. All time-critical work happens here. Time domains, agent behavior, MIDI event processing, and the scene graph live in the engine.

- **Scripting:** Python, embedded in the C++ engine. Chosen for familiarity, AZERTY-friendliness, ecosystem, and audience legibility of the resulting DSL. A custom vocabulary layer on top of Python provides the domain-specific verbs and objects.

- **3D rendering:** bgfx. Cross-platform rendering abstraction. Sufficient for the gritty, primitive-based aesthetic; mature enough to ship. Rendering happens in the C++ engine, into an offscreen texture handed to the UI layer.

- **UI layer:** Flutter. Hosts all 2D interface — patcher canvas, code editor, state graph, MIDI editor, mixing controls — and displays the 3D scene via a texture shared from the engine. Chosen for fast iteration, polished visuals, and an ecosystem the developer already knows. A Dart wrapper exposes the C++ engine over FFI.

- **Target platform:** Windows, initially. Cross-platform is possible later if useful, but is explicitly out of scope for the foreseeable phases.

The division of responsibility: **the engine owns the Scene; the UI is a window onto it.** This is the key architectural decision. Spatial relationships, agent behavior, and timing all live where the audio lives, so cross-layer influence does not pay an FFI cost on every frame. The UI sends user actions to the engine and receives updates back, but the authoritative state is in C++.

## 6. Open Questions and Deferred Decisions

The following are noted explicitly so they are not forgotten.

- **The DSL vocabulary.** What verbs, what objects, what naming conventions. Postponed until the basic engine extensions and UI scaffolding are working enough to play with.
- **State persistence format.** How a performance is saved. Probably JSON for the scene description plus paths to assets, but the format will be designed alongside the first useful set of features.
- **Controller integration.** Which controllers to support first, how mappings are defined, whether mappings live in code or in a separate UI. Deferred.
- **Audio-rate vs. control-rate cross-layer influence.** Where exactly the boundary sits, and how the performer expresses the difference. To be decided in implementation, not in advance.
- **Hot-reload semantics for Python.** What happens to running audio and active agents when a script is re-evaluated. Probably scoped redefinition, but the exact rules need to be worked out.
- **Audience legibility tooling.** The "projected view" of the code, the visual feedback on what just changed, the highlighting system. A whole subsystem in itself, deferred but not forgotten.
- **Plugin hosting (VST/AU).** Not in scope at present. May or may not become so.
- **Recording the performance.** Audio recording, scene recording (so a performance can be replayed or re-navigated), or both. Out of scope initially.

## 7. Why This Document Exists

This is a private document. It exists so that the shape of Phi survives the long stretches when I am not working on it, and so that I can return to my own thinking without reconstructing it from scratch.

The shape will change as Phi gets built. That is fine. The principles in section 2 are the things I want to hold onto: no hierarchy, pluralistic time, semantic 3D, performative bias, multiple surfaces, audience legibility, flexibility over rigidity. The architecture in section 3 is one way to realize those principles. If something better suggests itself during implementation, this document should be updated, not deferred to.
