# CLAUDE.md

Workflow rules for Claude Code sessions on the Phi project. Read at session
start. Pair with [docs/PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md).

## How we work

1. **Issues first.** Every bug, feature, or enhancement is filed as a
   labelled GitHub issue *before* code is written. Branch from `develop`
   as `<issue-number>-<short-slug>` and PR back into `develop` through CI;
   `main` is protected and release-only, reached via a `develop → main`
   PR. The only exception is a trivial doc fix.
2. **Tests where sensible** (not dogmatically). Pure domain logic, the
   engine bridge, and end-to-end paths get tests first. Widget tests follow
   widget implementation. One-off scripts and animation tweaks don't need
   tests.
3. **One class per file.** Filename = `snake_case(ClassName)`. Folders are
   cheap; bundling classes is friction.
4. **Layered structure.** `core/` → `platform/` → `domain/` → `design/` →
   `engine/` → `shell/`+`surfaces/` → `app/main`. One-way dependencies.
   `platform/` holds OS facilities outside the engine (pure Dart +
   `dart:ffi`, no Flutter). Update `docs/PROJECT_OVERVIEW.md` after
   structural changes.
5. **Design tokens come from `design system/colors_and_type.css`.** Dart
   tokens under `lib/design/tokens/` are derivations — keep them in sync.
6. **User docs follow behaviour.** A change users can see updates the
   matching page under `docs/user/` in the same PR. Shortcuts are declared in
   the command registry or a surface's `*_shortcut_hints.dart` table;
   `keyboard_shortcuts_doc_drift_test.dart` fails until
   `docs/user/keyboard-shortcuts.md` matches them.

## Label taxonomy

Created during Phase 0 and applied to every issue.

- **type:** `type:bug`, `type:feature`, `type:enhancement`, `type:task`,
  `type:docs`
- **layer:** `layer:scene`, `layer:dsp`, `layer:spatial`,
  `layer:time-domains`, `layer:patcher`, `layer:live-coding`, `layer:midi`,
  `layer:state-machine`, `layer:mix`, `layer:shell`, `layer:design`,
  `layer:engine-bridge`, `layer:infra`
- **priority:** `priority:p0-now`, `priority:p1-soon`, `priority:p2-later`,
  `priority:p3-maybe`
- **status:** `status:triaged`, `status:blocked`, `status:in-progress`

Pick at least one `type:` and one `layer:`. Priority and status are
maintainer-applied.

## Running locally

Requires Windows or Linux (x64) and Flutter at the **pinned master revision**
in `.fvmrc` (#478), for the experimental multi-window API. Stable does not
resolve: `pubspec.yaml`'s `environment:` floors are that revision's versions.
The 3D Scene view is drawn by `flutter_scene` on Flutter GPU (#455); both runners
switch Flutter GPU on. `flutter test` has no Impeller, so there the view shows its
"unavailable" notice and only integration tests see it draw. `yse` (^0.2.0)
comes from pub.dev; its native-assets build hook downloads and bundles the
engine (`libyse.dll` next to the executable, `libyse.so` in `bundle/lib/`), so
no engine setup is needed.
`YSE_DLL_PATH` (a directory) still takes precedence, for testing against a
local engine build. See [README.md](README.md).

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

### The Flutter SDK: pinned master

On the Linux dev machine, `~/flutter` is stable and stays the default for
every other project. `~/flutter-master` is a full clone of `flutter/flutter`,
checked out (detached) at the commit in `.fvmrc`. `~/.local/bin/flutter` and
`dart` are a shim that picks the SDK by the current directory from
`~/.config/flutter-sdk/map` (the line `/home/phi/dev/phi
/home/phi/flutter-master`); everything else falls back to `~/flutter`.
`~/.local/bin` has to come before `~/flutter/bin` on `PATH`, or the shim never
runs. Inside the repo, `flutter --version` must report the pinned revision
(`channel [user-branch]` is expected on a detached checkout). The windowing
flag is on: `flutter config --enable-windowing`, run once from inside the
repo. It lands in the shared `~/.config/flutter/settings`; stable lists it as
"(Unavailable)" and ignores it.

To bump the pin, follow "Toolchain" in
[docs/PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md). A bump is its own PR.

### Integration tests on Linux: always headless

Never run an integration test on the real desktop. Its windows take over the
developer's screen. The Linux dev machine runs Wayland, so plain `xvfb-run`
is **not** enough: GTK ignores the Xvfb display and opens on the real screen.
Use exactly this command, including for background loops, repeat runs and
extra worktrees:

```bash
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 xvfb-run -a -s "-screen 0 1920x1080x24" \
  flutter test integration_test/<file>.dart -d linux
```

Without `-s`, Xvfb's screen is 640x480, smaller than the 1920x1080 the tests are
sized for. When you hand integration work to a subagent, paste this command
word for word.

## Boundaries

- **Don't** push to `main` without confirmation.
- **Don't** skip hooks (`--no-verify`) or bypass signing.
- **Don't** import `package:yse/...` outside `lib/engine/bridge/` — the
  engine façade is the only place the FFI surface is touched.
- **Don't** put Flutter imports into `lib/domain/` — domain stays pure Dart.
- **Do** file an issue on `yvanvds/dart-yse` when the bridge needs new
  capabilities, rather than working around the wrapper.

## Memory

There is a Claude Code memory store for this project under
`~/.claude/projects/d--phi/memory/`. It captures durable preferences and
project facts that survive between sessions.
