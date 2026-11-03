# Shell — tabs, splits, layout persistence, command palette

> Detail doc #9 of [phase2-direction.md](../phase2-direction.md) §4.9.
> Design record, 2026-07-19 — reviewed; decisions in §7. Leads to the
> "shell layout" epic on `yvanvds/phi`.
>
> **Depends on:** nothing unimplemented — the shell, project manifest,
> and settings are shipped code. The multi-window question ended in a
> research spike (§5). Phi has since adopted the official windowing API on
> a pinned Flutter master (#478, #481); see §5.5. The Scene is proven to
> draw in a second native window (#297); see §5.6.

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
  GL paths). *Since #455 the Scene is an ordinary widget on Flutter GPU,
  with no platform view or external texture, and integration tests see
  it draw.*

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

## 5. Multi-window — spike findings (2026-07-20)

The wide-screen case is served first by splits in one maximized
window (§2). True multi-window (laptop + external, later the projected
audience view) had a real technical question. This section records the
**timeboxed research spike** (issue #256, `type:task`): the two routes
evaluated against Phi's constraint set, what one window genuinely
fails to serve, and the decision — **defer, with the official
same-isolate windowing API as the strategic target**. That deferral has
since been lifted: Phi adopted the API on a pinned master revision in
2026-11 (§5.5).

### 5.1 The constraint set (verified against the code)

Two facts decide this, and both were confirmed in the tree, not
assumed:

- **Two process-wide, single-isolate singletons.** The native audio
  engine is reached through yse's `System.instance`
  (`RealYseGateway`), and the Scene viewport's GL renderer is
  macbear's `M3AppEngine`, described in
  `macbear_scene_renderer.dart` as a *process-wide singleton* mounted
  in exactly one place. Neither can exist twice in the process.
- **All app state is main-isolate-local.** The registry, the
  lifecycle/shell/engine controllers, and `SessionState` all live in
  the root isolate; there is **no `dart:isolate` usage anywhere in
  `lib/`**. Phi has never needed a second isolate and has no
  cross-isolate protocol to build on.

So a secondary window is cheap only if it shares this one isolate and
one engine. If it runs in its own isolate, it can touch neither
singleton without a hand-built mirroring protocol — and the GL
viewport, whose external `Texture` registration is *engine-scoped*,
could not be reached at all from a second engine.

> **Update (#455, 2026-11).** macbear and its `M3AppEngine` are gone. The
> Scene is drawn by `flutter_scene` on Flutter GPU, with no external
> `Texture`. The conclusion holds: all app state still lives in one isolate.

### 5.2 Route A — official same-isolate multi-view / windowing

Flutter's first-party windowing API (`WindowingOwner` /
`RegularWindow` / `RegularWindowController`, layered on the multi-view
`runWidget` + `View` / `ViewCollection` foundation, contributed by
Canonical as the successor to flutter/flutter#30701) is **exactly**
Phi's shape: every window shares one isolate and one engine, so the
registry, controllers, and the yse/macbear singletons are directly
reachable from a second window with **no ports and no state
mirroring**, and the engine-scoped GL texture is architecturally
shareable across views.

The catch is maturity. As of this spike Phi is on **Flutter 3.44.0,
stable channel** — and on that release the windowing API is
**experimental, main-channel only, gated behind `flutter config
--enable-windowing`, and explicitly "not for production."** It moved
fast (engine foundations in 3.35, the flag + a win32 `RegularWindow`
in 3.38, an experimental cross-desktop API in 3.44 with Canonical now
the desktop steward, and Windows the lead platform for regular
windows), but it is **not on Phi's channel yet**. Adopting it today
would mean pinning off stable and absorbing API churn and open bugs.

> **Update (#478, 2026-11).** Phi now does exactly that. It tracks a pinned
> Flutter master revision (`.fvmrc`) with `enable-windowing` on, so that
> subpatches can open in their own window (#481). By that revision the
> names had changed: `RegularWindowController` / `RegularWindow` are now
> `WindowController` / `Window`. The full list at the pin is under
> "Toolchain" in `docs/PROJECT_OVERVIEW.md`.

One residual unknown even on Route A: whether the ANGLE/macbear GL
texture actually renders into a *second window's* `FlutterView`.
Flutter's multi-view umbrella (flutter/flutter#142845) still lists
open secondary-view texture/platform-view work, so this must be
proven by hand, not assumed — filed as **#297**. *Answered in §5.6, for
the Flutter GPU renderer that replaced the GL texture.*

### 5.3 Route B — `desktop_multi_window` (separate isolate)

The stable-today community route (`desktop_multi_window`, mixin.dev,
~v0.3.0) gives **each window its own Flutter engine and isolate**.
Method channels cannot cross engines, so the second window would need
a bespoke IPC/state-mirroring protocol over ports for the registry
and session, per-engine plugin re-registration, and per-engine texture
handling. For a *read-mostly* secondary window (say a static "now
playing" or transport mirror) that protocol is a bounded but real cost
— a snapshot pushed over a `SendPort` and rebuilt on the far side. For
a *fully interactive* second window it is prohibitive: every
controller mutation, undo scope, and the shared engine/GL singletons
would have to be marshalled both ways, effectively duplicating the
state Phi deliberately centralizes — and the GL viewport still could
not be shared, because its texture belongs to the first engine.

The decisive point: this is a large amount of scaffolding we would
**tear out** the moment Route A reaches stable. It buys a second
window sooner at the price of building the exact thing the official
API exists to make unnecessary. Route B was never adopted, and Phi has no
`desktop_multi_window` dependency.

### 5.4 Route C — wait: what one window actually fails to serve

Enumerating the concrete scenarios (not a hypothetical want):

1. **Laptop + external display.** Real, but **served by splits
   today** — a maximized split-tree window on the external screen is
   the wide-screen answer §2 already ships. The only thing one window
   cannot do is span *two physical displays at once* (e.g. edit on the
   laptop panel while the mix fills the external). That is an
   ergonomic nicety, not a blocker: the performer maximizes on the
   larger screen.
2. **Projected audience view** (vision §4). This is the one scenario
   splits **cannot** serve — a second output showing a different,
   audience-facing view (the Scene, without performer chrome) on a
   projector while the operator screen keeps the workstation. It needs
   a genuinely separate window on a second display, and it is
   GL-texture-bound, which is why #297 is its gating risk. *No longer
   texture-bound since #455, and the risk is retired (§5.6).*
3. **Everything else** (side-by-side mix + clip while performing,
   panel arrangements) is already the split shell's job (§2), not a
   multi-window need.

So the honest tally: of the scenarios that motivated the question, one
is already solved by splits, one is a nicety, and only the **projected
audience view** is a true multi-window requirement — and it is a
*future* feature with its own design still ahead (§6).

### 5.5 Decision and follow-ups

**Defer implementation. Adopt Flutter's official same-isolate
windowing API as the strategic target; do not build a separate-isolate
protocol we would later delete.** The only true multi-window need
(the projected audience view) is future work, and the official route
that fits Phi's singleton/one-isolate constraints is real but not yet
on the stable channel. Waiting costs nothing today; building Route B
would cost a throwaway IPC layer.

Follow-ups filed:

- **#296** — watch/tracking item (the recorded deferral): re-evaluate
  when the windowing API reaches **beta/stable**, or when a concrete
  scenario forces the projected audience view. When it fires, the
  secondary window is designed as just another `View`/`RegularWindow`
  over the shared session — no new isolate. *Closed by the 2026-11
  adoption below.*
- **#297** — timeboxed prototype (do-not-ship, main channel behind
  `--enable-windowing`): retire the single Route-A unknown by proving
  the ANGLE/macbear GL viewport renders into a second window's view,
  or record the fallback. *Answered in §5.6, with a kept test instead of
  a discarded prototype.*

No implementation lands in this epic. The projected audience view
(vision §4, §6) waits on #296/#297 by design.

#### Adopted on a pinned master (2026-11)

#296's trigger fired by decision, not by a Flutter release. Phi is far
from a release, so the maintainer chose to track Flutter master and use
Route A now, rather than wait for beta/stable:

- **#478** pinned Phi to a Flutter master revision (`.fvmrc`, read by every
  CI job) with `flutter config --enable-windowing` on. The pin, the API
  names at that pin and how to bump it are under "Toolchain" in
  `docs/PROJECT_OVERVIEW.md`.
- **#481** is the first user: a subpatch opens in its own top-level window
  (`WindowController` / `Window`, the renamed `RegularWindowController` /
  `RegularWindow`). The `Window` views hang off a `ViewAnchor` /
  `ViewCollection` in the main widget tree, in the main isolate, over the
  same `PatcherController` and journal as the main window
  (`lib/surfaces/patcher/subpatch/`). This is Route A exactly as §5.2
  described it: no second isolate, no ports, no state mirroring.

What remains provisional, and is tracked in **#554**:

- The API is **`@internal`** and not exported from a public library. Phi
  imports `package:flutter/src/widgets/_window.dart` (and
  `src/foundation/_features.dart`) under
  `ignore_for_file: invalid_use_of_internal_member, implementation_imports`,
  so a pin bump can rename or reshape it.
- It is still **master-only and behind `enable-windowing`**. Phi cannot
  build on beta/stable until the API ships there, and CI enables the flag
  in every job.

When the API is public and on a channel release, #554 moves the imports to
the public library, drops the flag step, and takes Phi off the master pin.
Subpatch windows are plain Flutter UI, so they did not need the
secondary-window rendering answer. §5.6 gives it.

### 5.6 The Scene in a second window — result (#297, 2026-11)

**It works.** The Scene view draws in a second native top-level window over
the one engine and isolate, with no fallback needed. The question changed
shape on the way: #455 replaced the external GL texture with `flutter_scene`
on Flutter GPU, so nothing is registered per engine or per view any more.
Flutter GPU has one process-wide context (`gpu.gpuContext`). A `SceneView`
renders into offscreen textures and draws them onto its canvas through
`Texture.asImage`, so to the window it is ordinary Flutter content. The
fallbacks #297 listed (a second `Texture` sink, a non-GL projection) are moot.

The proof is kept as a regression guard for the audience view:
`integration_test/native_windows/scene_audience_window_test.dart`. The real
`PhiApp` runs the workstation in the main window with the Scene open, and a
real `WindowController` window mounts the same renderer's view.

**Verified**, on Linux X11 under Xvfb (Mesa llvmpipe) at the pinned revision, and
on `windows-latest` except for the display readback, which is Linux only there
(on Windows the checks stop at the Flutter layer):

- The window is a view the engine made, and every agent draws in its voice
  colour where the pick math projects it. This is checked in the Flutter layer
  and in the pixels the window shows on the display, read back from the window
  system (`LinuxWindowPixels`). Layer readback alone would pass on a window
  that never presents.
- Both windows draw the one graph at once, each at its own size.
- A drag in the window orbits the camera and the window redraws. The drag is
  flutter_test's pointer events addressed to the window's view.
- `setSize` resizes the native window and the Scene in it.
- The window keeps showing the Scene when the main window moves to Mix.
- Closing it returns the app to one view.
- Pixel ratio: the `SceneView` reads the ratio of its hosting view. One manual
  run with `GDK_SCALE=2` gave ratio 2.0 and passed the same checks at twice the
  pixels.

**Not verified:**

- **Windows.** The test joins the integration sweep through
  `tool/run_integration_tests.ps1`, so CI runs it there, but it has not run
  there yet. Its display readback is Linux only, so on Windows it checks the
  layer and not what the window presents.
- A real X11 session, Wayland, and a real GPU.
- OS pointer input reaching the window, a second physical display, and two
  displays with different pixel ratios.

**Caveats for the audience view's design:**

1. **Visibility belongs to the renderer, not the view.**
   `FlutterSceneRenderer.setVisible(false)` stops all redraws, and the shell
   calls it when the Scene tab goes offstage. Measured: with the main window on
   Mix, an orbit in the audience window moved the camera while the window kept
   its old frame, until `setVisible(true)` flushed it. Agent updates go through
   the same gate (`_markDirty`), so as things stand the audience view would
   freeze whenever the performer leaves the Scene tab. The renderer has to stay
   live while any view of it is on screen. The test does not pin the current
   behaviour.
2. **One camera, one pointer controller.** Orbiting in either window moves both
   (the test asserts this as today's shape). From the source, not measured:
   disposing either view calls `pointer.cancelAll()`, so closing the audience
   window cancels a grab in the main window. An audience view probably wants
   its own camera and no input.
3. **Two views of one `fs.Scene` share its render targets.** From the
   `flutter_scene` 0.24.3 source, not measured: each `SceneView` renders as
   view 0 of the scene's `Surface`, which keeps targets per output size, two
   sizes at most, with a ring of two swapchain textures per size. Two views at
   different sizes get separate rings, as in the test. At the same size they
   take turns on one ring and use it up every frame, so a texture from the
   previous frame can be overwritten while the compositor still reads it. A
   third size would evict and reallocate every frame. Before showing the graph
   in more than one place at equal sizes, give the audience view its own scene
   or use `renderViews`.
4. **Linux X11: open windows after the first paint.** A window made before the
   main window's first GTK paint exits the app with a GLX `BadAccess`. This has
   nothing to do with the Scene: a plain coloured box triggers it, and the cause
   is the EGL context the engine leaves current for secondary views. No Phi code
   does this today, but restoring an audience view at boot would. Mechanism and
   evidence are in **#556**, which also tracks reporting it upstream.
5. **Linux: a new window's first frame is 1x1.** The engine adds the view at
   that size and GTK allocates the real one afterwards, so anything laid out in
   a new window must survive a 1x1 layout without reporting an overflow.
   `SubpatchWindowView` draws nothing until its bar fits (#557).
6. **Windows: hold the Scene still while a window opens.** A new view leaves the
   raster thread with no GL context until the next frame, and a Flutter GPU
   submit landing in that gap aborts the app in Impeller. Nothing in Phi opens a
   window with the Scene on screen today, but the audience view will. Until the
   engine is fixed it must do what the test does: `setVisible(false)`, make the
   window, let a plain frame draw, `setVisible(true)`. Mechanism in **#559**.

**Testing native windows.** The stock integration binding cannot make one
(flutter/flutter#195919: it installs a stand-in owner, and its dispatcher
reports a fake engine id, which the Linux owner dereferences). The binding can
in fact be replaced: `flutter_test_config.dart` runs before the entry point
creates its binding. Tests under `integration_test/native_windows/` get
`NativeWindowsTestBinding`, which keeps the platform owner and reports the real
id. The subpatch window test runs there too (**#557**): text input goes to the
real plugin, and the keys are real on both platforms, through XTEST on Linux and
`SendInput` on Windows (**#558**). Both tests run on `windows-latest`, where the
test can move the foreground between its windows with `SetForegroundWindow`, so
`SendInput` reaches the window it means. The binding also drops real mouse events
for a window whose widgets have gone, because flutter_test throws on them.

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
