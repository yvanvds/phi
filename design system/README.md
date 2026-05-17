# Phi Design System

> A workstation for live electronic music performance.
> Dark, gritty, glowing. Fuchsia on black. Closer to an oscilloscope than a video game.

---

## About Phi

Phi is a forthcoming desktop application: a flexible workstation for performing electronic music live. Where traditional DAWs assume a master clock and a linear timeline, Phi treats **time as pluralistic** (many clocks, weighted subscriptions, drift and lock), **3D space as semantic** (position, proximity and velocity carry musical meaning), and **layers as non-hierarchical** (any surface — 3D scene, patcher, live code, MIDI, state graph — can influence any other).

The product is built on a custom audio engine (yse-soundengine, C++) with a Python scripting layer, bgfx-rendered 3D, and a Flutter UI shell. **Target platform: Windows.**

This design system codifies the visual language Phi presents to its performer and — critically — to the audience watching a projected display during a show.

## Sources

This design system was created from a long product brief (architecture, conceptual layers, performance experience, technology stack). **No codebase, Figma file, or existing visual artifacts were provided** — every visual decision in this folder is a first interpretation of the brief, intended as a starting point for iteration.

Where a decision was made on the design system author's own initiative (font choices, exact hex values, icon library), it is flagged in this README so the Phi author can pin down the real choice.

## Index

```
.
├── README.md                  this file
├── SKILL.md                   instructions for AI agents using this system
├── colors_and_type.css        CSS variables: type, color, spacing, motion, radii
├── assets/
│   ├── logo-mark.svg          φ mark, scope-trace style
│   ├── logo-lockup.svg        mark + wordmark
│   └── wordmark.svg           "PHI" wordmark only
├── fonts/                     (Google Fonts loaded by CSS — see Type section)
├── preview/                   small HTML cards for the Design System tab
│   ├── type-*.html
│   ├── color-*.html
│   ├── spacing-*.html
│   ├── component-*.html
│   └── brand-*.html
└── ui_kits/
    └── phi-workstation/       interactive mock of the workstation UI
        ├── README.md
        ├── index.html
        └── *.jsx
```

---

## Content Fundamentals

**Voice.** Phi is a tool for a single, technically capable performer. Copy speaks **directly to the performer** — second-person ("you") only when necessary, otherwise instruction-mood and noun phrases ("Subscribe agent to domain", "Arm transition", "Open scope"). Never marketing voice, never "we / our". Never apologetic. The product brief itself models the tone — declarative, opinionated, slightly austere.

**Casing.**
- **UI labels:** lowercase with strategic capitalization. *"subscribe", "domain", "lock phase"*, not *"Subscribe"*.
- **Section headers / panel titles:** UPPERCASE in mono, with widened tracking. *"DOMAINS"*, *"SCENE"*, *"CODE"*. This is the oscilloscope register — labels on a piece of equipment.
- **Inline / running text:** sentence case.
- **Section/object names made by the performer:** verbatim, never auto-capitalized.

**Numbers and units.** Always present. Phi is a measurement instrument as much as an instrument; show values. **`118.4 BPM` / `4:7` / `+3.2 st` / `−12.4 dB` / `0.382 cohesion`.** Use a non-breaking thin space before units. Prefer mono for any number that updates live.

**Code.** Code is a first-class surface in the product, so it is a first-class surface in the marketing too. Show code snippets unapologetically; do not pseudo-code. The on-screen DSL is verb-first and reads like English: `swarm.cohere(0.6)`, `domain "drum" tempo 124`.

**No emoji. Ever.** Phi is for performers operating in low light on a live stage. Emoji are visually noisy and culturally wrong for this product. If you reach for a sparkle, stop.

**No exclamation marks** in product or marketing copy. The aesthetic is composed, not enthusiastic.

**Example phrases.** "Time is pluralistic." "No master clock." "Code is one surface among several." "Pull the agent into the gravity well." "Arm transition · 4 bars · drum domain."

---

## Visual Foundations

### Color

The substrate is a **deep, slightly cool near-black** — never `#000000`, which feels dead. The default canvas is `--bg-0` (`#0a0d10`); panels and surfaces stack from there. Light comes from **emissive accents** ("voices"), not from raised cards.

Six voices form the accent palette: **fuchsia, cyan, amber, phosphor green, violet, signal yellow**. They are numbered (`--voice-1` … `--voice-6`), not named, because the performer assigns them — to a time domain, a swarm, a code block, a state node — and the meaning is performance-dependent. Voice 1 (bright fuchsia) is the default "live / armed" indicator, used when no assignment has been made. The choice of fuchsia as the canonical voice is personal to Phi's author and informs the entire brand identity.

Status colors (`--hot` / `--warm` / `--cool` / `--live`) are reserved for fixed semantics: clipping, attention, monitor, transmitting. They do not double as voices.

**Special case — audio peak meters do NOT use voice color.** The peak meter on a channel strip follows the universal audio convention: **green for normal level, amber from −12 dB upward, red approaching clip**. The channel's own voice color (whatever it has been assigned) is reserved for the strip's header dot and master-strip glow — the metering uses `--voice-4` (phosphor green) → `--voice-3` (amber) → `--hot` (red), regardless of channel voice. This is the only place where a voice token is hard-locked to a semantic; it would be too confusing to flip the meaning of "red on a fader" per channel.

### Type

Three families. **Rubik Glitch** for the largest brand registers (`display-xl`, `h1`, and the wordmark) — a Google Fonts display face with chromatic-shift / glitch character built into every glyph. **Instrument Sans** for body UI (`h2`/`h3`, body, small). **JetBrains Mono** for code, readouts, numbers, and panel labels — engineered for legibility, which matters specifically because the brief calls for projected code to be readable from the audience.

Rubik Glitch is single-weight and intentionally hard to read at small sizes — confine it to `display-xl`, `h1`, and the wordmark. Never use it for body copy, buttons, or anything below 14px.

> 📦 **Implementation note for Flutter / Claude Code:** all three families are on Google Fonts and load with the `google_fonts` Flutter package or the standard CSS @import at the top of `colors_and_type.css`. No paid faces, no custom variation axes — each face is one weight, one file.

The display sans runs **tight** (`-0.02em`). Mono runs at standard tracking; panel labels (caption register) go **uppercase, widened, 11px**. Rubik Glitch is left at standard tracking (the glyphs themselves carry the character).

Display sizes top out large (88px) — used sparingly, e.g. a marketing title or the splash screen — because Phi's working UI is information-dense and the display register exists for the few moments when the product can breathe.

### Spacing & layout

A `4px` base unit, scaling at `2 / 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64 / 96`. Most internal padding is `8` or `12`; section gaps are `24` or `32`. The workstation UI is built on a **16px grid** — visible as a faint dotted backdrop in the 3D scene viewport, the patcher canvas, and the state graph.

Layouts are **rectilinear, mostly tiled, no centered single-column compositions**. Phi is a multi-panel workstation. Borrow from DAW / modular / oscilloscope chrome: panels packed edge-to-edge, hairline dividers, sticky toolbars top and bottom of each panel.

### Backgrounds & motifs

- **No gradients as primary fills.** A gradient is only ever a "protection" wash beneath text over a busy 3D scene, or the soft halo around a glow.
- **No stock imagery, no hand-drawn illustrations.** The brand draws on signal-processing visuals — particles, vectors, scope traces, grids, waveforms. Where a product page needs a hero, it shows a still from the 3D scene.
- **Texture.** A subtle 16px grid lives on every dark surface (`--grid-color`). On glowing surfaces (the 3D viewport, code register), add a *very* light film grain to evoke phosphor.

### Borders, cards, elevation

Cards have **hairline borders** (`--line-1`, 1px), small radii (`--r-2` = 4px), and a near-flat background offset from the canvas by a single step (`--bg-1` → `--bg-2`). **Real drop shadows are minimal** — Phi uses **glow** as its elevation language. An "active" or "armed" element gets a soft phosphor glow (`--glow-1`), not a shadow.

### Radii

**Small or zero.** `--r-0` (0px) for tightly-packed workstation chrome and panel boundaries. `--r-1` (2px) for inputs. `--r-2` (4px) for cards, buttons. `--r-pill` only for live tags / status capsules. Never larger.

### Hover & press

- **Hover:** background steps up one level (`--bg-1` → `--bg-2`). No color shift on the element itself. Text never changes color on hover — it is already at the right contrast.
- **Press:** background steps up two levels (`--bg-3`), and the element is offset down by 1px (`translateY(1px)`). No shrink, no bounce.
- **Armed / live:** the element grows a fuchsia border (`--line-hot`) and a soft glow (`--voice-1-soft`). Glows **pulse** at a slow continuous rate using a sine on opacity (0.6 → 1.0 → 0.6) over ~1.2s. Never a hard blink.

### Motion

Phi's motion is **physical and signal-like**: fast attack, exponential decay. Durations are short — `90ms` for state changes, `160ms` for menus, `280ms` for panel transitions. Easing is `cubic-bezier(0.16, 1.0, 0.3, 1.0)` for almost everything (a hard-out ease). **Never `ease-in-out` with a long duration. Never bouncy springs.** The exception is morphing state transitions in the product itself, which are user-driven and can run for bars of music — these are not UI animations, they are musical events.

### Transparency & blur

Used sparingly. The 3D scene viewport may have a **top + bottom protection gradient** (10% black → 0%) so toolbars over it stay legible. Backdrop blur is used only on floating overlays (command palette, transition-arm dialog) — `backdrop-filter: blur(20px) saturate(140%)`, over `rgba(10, 13, 16, 0.7)`.

### Imagery & screenshots

When a screenshot or scene still is shown, **let it stay dark**. Do not "lift the shadows" or auto-contrast. Phi is dark because the product is dark; performance imagery should preserve that. If colour-grading is needed: pull saturation down ~15%, lift the deep shadows just barely. Cool cast preferred (slight cyan in the blacks).

### Fixed elements

The workstation UI has these fixed regions:
- **Top toolbar** (32px tall) — transport, time domains summary, scene name, projection toggle.
- **Left rail** (44px wide, icon-only) — surface switcher (Scene / Patcher / Code / State / MIDI / Mix).
- **Right inspector** (collapsible, 280–360px) — properties of selected object.
- **Bottom status strip** (24px) — CPU, latency, audio buffer health, MIDI activity.
- **Center** — the active surface, full remaining space.

---

## Iconography

> ⚠ **Substitution flag.** No icon system was provided. This design system links **Lucide icons** (CDN) as a substitution — chosen for the thin (1.5px) stroke, geometric construction, and rectilinear character that match Phi's aesthetic. If the eventual product uses a different set (likely something custom, given the unusual primitives Phi needs — agents, swarms, domains, voices), replace `lucide` calls with the real assets.

**Usage rules.**

- **Stroke icons only.** No filled icons in product chrome.
- **Stroke weight: 1.5px** at 16/20/24px sizes. Heavier strokes feel toy-like; thinner disappear at projection distance.
- **Sizes: 14, 16, 20, 24px.** The 14px register is for inline annotations only.
- **Color: inherit from text** by default (`currentColor`). When an icon represents a live / armed state, color it with the relevant voice and add a small glow.
- **No emoji.** Reiterating from Content Fundamentals.
- **No unicode characters as icons** except for these specific mathematical/musical glyphs which belong to the brand:
  - `φ` — the Phi mark itself (the brand letter)
  - `∅` — empty domain / unsubscribed
  - `≈` — drift / loose-lock
  - `=` `≠` — phase locked / unlocked
  - `→` `↔` — transition arrow in state graph
  - `▸ ▾` — disclosure
  - These are kept set in JetBrains Mono so they match the surrounding chrome.

**Custom primitives.** Phi has a small set of icons that no general library will supply: an **agent** (small circle with motion vector), a **swarm** (cluster of agents), a **domain marker** (clock dial split into segments), a **state node** (rounded square with corner pins), a **voice swatch** (colored square). These exist as inline SVGs in the UI kit; when the real product ships, they will need bespoke artwork.

---

## Logo & wordmark

- **`logo-mark.svg`** — the φ glyph, rendered as a scope trace: a fuchsia stroke on transparent. Use this as the app icon, favicon, and small-scale brand mark.
- **`wordmark.svg`** — `phi` set in **Rubik Glitch**, lowercase. Always lowercase. The Greek letter (φ) and the Latin spelling (`phi`) are interchangeable; pick one per surface, never both side by side.
- **`logo-lockup.svg`** — mark + wordmark, baseline-aligned, with one `var(--s-3)` gap.

Minimum size for the mark: 16px (favicon). Minimum size for the wordmark: 12px cap-height. Clear space around any version of the logo: at least one cap-height of `phi` on all sides.

The mark may appear in any voice color when used as a "voice swatch" indicator (assigning a brand mark to a domain or scene file in the project browser), but the **canonical mark is bright fuchsia** (`--voice-1`).

---

## What's in the UI kit

The `ui_kits/phi-workstation/` folder contains:

- **`index.html`** — an interactive mock of the Phi workstation. Loads the surfaces (3D scene, patcher, code editor, state graph, MIDI editor, mixer) inside a Flutter-style window, with a tab-rail to switch between them and a few live-feeling micro-interactions (transport, transition arm, code re-eval flash).
- JSX components for each surface, factored small and reusable.

This is **a recreation of how Phi might look**, not a recreation of an existing product (there isn't one yet). The Phi author should treat this as a v0 visual proposal and tear it up.

---

## Caveats — read me first

1. **No source material.** No codebase, Figma, or screenshots were available. Every pixel here is my interpretation of the prose brief; the closer Phi gets to real, the more this should be replaced.
2. **Font choices flagged.** Rubik Glitch (display + wordmark), Instrument Sans (body UI), JetBrains Mono (code). All Google Fonts. Confirm or swap.
3. **Icon substitution.** Lucide via CDN. Confirm or swap.
4. **The "voices" palette.** Six colors, with voice-1 = bright fuchsia per the Phi author's preference. The other five (cyan, amber, phosphor green, violet, signal yellow) are still opinionated.
5. **The brand mark.** A φ scope-trace was my call. Phi may want something completely different (a wordmark only, an abstract mark, no mark).

---

*Use the Design System tab in the project sidebar to browse the visual cards.*
