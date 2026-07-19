# Shell — tabs, splits, layout persistence, command palette

> Detail doc #9 of [phase2-direction.md](../phase2-direction.md) §4.9.
> Design record, 2026-07-19 — reviewed; decisions in §7. Leads to the
> "shell layout" epic on `yvanvds/phi`.
>
> **Depends on:** nothing unimplemented — the shell, project manifest,
> and settings are shipped code. The multi-window question ends in a
> research spike, not a promise.

## 1. The problem

Phi is one window showing one surface at a time behind a rail switch.
On a wide external screen that wastes most of the glass; during a
performance it forces modal surface-hopping (you cannot watch the mix
while editing a clip); and every recent epic added panels (clip
library, racks panes) that deserve side-by-side arrangements. There is
also no keyboard-first way to reach anything — no palette, no
discoverable shortcuts.

## 2. Shape of the solution

VS-Code-style **panes in a split tree, tabs in each pane**:

- The workstation's center area hosts a **split tree**: rows and
  columns of panes, resizable by splitter drag; each pane holds a
  **tab stack** of surfaces.
- **Surfaces are single-instance** (open question 2): one Mix, one
  MIDI, one Patcher… — dragging moves a surface between panes, never
  duplicates it. (Multiple views of one surface is a later, harder
  feature; nothing here precludes it.)
- **Drag a tab** to a pane edge to split (half → quadrant), to a pane
  center to join its stack, within a stack to reorder; closing a tab
  returns the surface to the "closed" set (reachable via rail or
  palette); the last pane never closes.
- **The rail stays** as identity + summon (open question 3): clicking
  a rail entry focuses the surface wherever it lives, or opens it in
  the active pane if closed. Muscle memory and the six/seven-icon
  identity survive; tabs do the arranging.
- Global chrome (top toolbar, bottom status, right inspector) stays
  outside the split area, unchanged.
- **Scene caveat:** the GL viewport re-parents when its tab moves;
  texture-backed platform views survive re-parenting, but this is the
  one interaction to verify by hand early (not CI-testable, like all
  GL paths).

## 3. Layout persistence

- The split tree + tab assignments + active tabs serialize into a
  **manifest section** (`project.json` — layout is part of the set, as
  the direction doc chose; a set built for the wide screen is part of
  that performance's design).
- Saved on save/autosave like everything manifest-borne, but **not
  journaled and not undoable** — layout is workspace arrangement, not
  authored content; recovery replay ignores it (the manifest's last
  save wins).
- **Fit fallback:** restoring a layout onto a smaller screen clamps
  splitter fractions (they are fractions, not pixels, so degradation
  is graceful by construction); a layout referencing a surface that no
  longer exists drops the tab silently.
- A fresh project seeds the current single-pane layout with Mix open —
  nothing changes until the performer splits.

## 4. Command palette

`Ctrl+Shift+P` (and `F1`) opens an overlay palette:

- A **command registry**: id, title, category, optional shortcut,
  enabled-predicate. The shell registers project ops (save, open,
  duplicate…), settings, surface focus/summon, transport (play, stop,
  panic-when-it-lands); surfaces register their own as they grow.
- Fuzzy search over title + category; recently-used first; the row
  shows the shortcut — the palette **is** the shortcut discoverability
  story.
- The registry is also where the **default shortcut map** lives —
  static in v1 (no rebinding UI; that is a later settings section),
  conflicts asserted in debug builds.
- Entity search ("jump to `clip.drums`") is deliberately *not* in v1
  (open question 4) — the registry-driven design makes it a cheap
  later addition to the same overlay.

## 5. Multi-window — a spike, not a promise

The wide-screen case is served first by splits in one maximized
window. True multi-window (laptop + external, later the projected
audience view) has a real technical question: Flutter's official
desktop multi-window support is still maturing, and the community
route (`desktop_multi_window`) runs each window in a **separate
isolate** — Phi's registry, controllers, and sessions are
isolate-local, while the engine is one native instance in the shared
process. A second window therefore needs either the official
same-isolate multi-view path (when it ships for Windows) or a
state-mirroring protocol over ports.

The epic ends with a **timeboxed research spike**: evaluate both
routes against the shared-engine / isolate-local-state constraint,
write the findings into this doc, and file the follow-up slice the
findings justify. The projected audience view (vision §4) waits on
that outcome by design.

## 6. Out of scope

- **Panel-level docking** (tearing the clip library out of the MIDI
  surface) — surfaces are the docking unit; panels stay inside.
- **Shortcut rebinding UI** — the registry supports it; the settings
  section arrives later.
- **Multiple views of one surface** — after multi-window resolves.
- **Projected/audience view** — its own design after the spike.
- **Touch/tablet ergonomics** — desktop-first, per the vision.

## 7. Review decisions (2026-07-19)

1. **Layout lives in the project manifest** — a set's arrangement is
   part of the set; fractions degrade gracefully on smaller screens.
2. **Surfaces are single-instance, move-not-duplicate** in v1.
3. **The rail stays** as identity + summon.
4. **Palette v1 is commands only** — entity search is a cheap later
   addition to the same overlay.

## 8. Proposed epic breakdown

Roughly seven issues, in dependency order:

1. Layout domain: split-tree + tab-stack model, fraction-based
   geometry, (de)serialization, fit fallback — pure Dart, TDD.
2. Workstation refactor: the center area renders the split tree;
   surfaces become dockable single-instance pane content; rail =
   focus/summon. Behaviour-neutral default (one pane, Mix open).
3. Tab + split interactions: tab strips, drag-to-dock zones
   (edges/center/reorder), splitter resize, close semantics.
4. Layout persistence: manifest section, restore-on-open with
   fallback, seed layout; explicitly journal-free.
5. Command registry + palette overlay: fuzzy search, recents,
   shortcut display; seed commands (project ops, settings, surface
   summon, transport).
6. Default shortcut map through the registry (existing bindings fold
   in; debug conflict assertion).
7. **Multi-window research spike** (timeboxed, `type:task`): official
   multi-view vs `desktop_multi_window` vs wait, against the
   shared-engine constraint; findings PR'd into this doc + follow-up
   issues filed.
