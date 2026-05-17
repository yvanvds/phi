# Phi Workstation — UI kit

An interactive, hi-fidelity recreation of the Phi workstation interface as proposed by this design system.

**No real product exists** — this is a v0 visual proposal. It demonstrates:

- The 6-surface architecture (Scene / Patcher / Code / State / MIDI / Mix) accessed from a single left rail.
- The fixed chrome: 36px top toolbar with transport + projection toggle, 44px left rail, 24px bottom status strip, and a collapsible right inspector.
- The voice-color system applied across panels — domains, swarms, code blocks, state nodes share a small palette.
- The motion language: fast phosphor flashes, no springs.

## Run

Open `index.html` directly — no build step. React + Babel are loaded from a CDN. Inline JSX is split across small files for readability:

```
index.html              shell + surface switcher
shared.jsx              voice color helpers, icons, small atoms (Capsule, Button, Field)
chrome.jsx              Toolbar, Rail, Inspector, StatusStrip
surface-scene.jsx       3D viewport mock (animated agents/swarms on canvas)
surface-patcher.jsx     node-and-cable DSP graph
surface-code.jsx        Python live-coding editor with re-evaluation flash
surface-state.jsx       performance state graph
surface-midi.jsx        MIDI clip + transformation chain
surface-mix.jsx         channel strips
```

## What's clickable

- The left-rail surface switcher (6 icons).
- Play / pause / arm / kill in the top toolbar.
- "Arm transition" in the state graph fires a 4-bar countdown that morphs into the new state.
- Code editor: click any line and press <kbd>⏎</kbd> (or the "eval" button) to flash-evaluate it.
- Right-inspector toggle, projection-mode toggle.

## What's *not* real

Everything. There is no audio, no real Python eval, no 3D engine. Numbers move on a timer to feel alive. This is a UI kit.
