# Phi

A flexible workstation for live electronic music performance. Personal,
single-developer, years-long project — not a product. Public so others can
read along.

The vision: polytemporal, spatially-aware electronic music shaped in real time,
on a substrate where no layer is master. See **[docs/phi-vision.md](docs/phi-vision.md)**
for the full design intent, and **[docs/PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md)**
for the current architectural snapshot. Architecture decision records also
live under [docs/](docs/) — start with
**[docs/timing-architecture.md](docs/timing-architecture.md)**.

## Status

**Phase 1 — audio hello-world.** A Flutter (Windows) shell renders the Phi
design system, and a single button in the Mix surface arms the engine's
built-in audio test signal via the dart-yse FFI bridge. Six surfaces are
planned (Scene · Patcher · Code · State · MIDI · Mix); only Mix has a stub.

## Stack

- **Engine:** [yse-soundengine](https://github.com/yvanvds/yse-soundengine) (C++).
- **FFI bridge:** [dart-yse](https://github.com/yvanvds/dart-yse) — package name `yse`.
- **UI:** Flutter ≥ 3.47.1, Windows desktop only for now.
- **Design system:** [`design system/`](design%20system/) — colors, type, motion,
  components. Source-of-truth for the Dart token files under `lib/design/tokens/`.

## Build

Requires Windows and [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.47.1.

```powershell
git clone https://github.com/yvanvds/phi
cd phi
flutter pub get
flutter run -d windows
```

The engine needs no manual setup. `yse` comes from pub.dev, and its
native-assets build hook downloads the libYSE release that version pins (once
per project, sha256-checked) and bundles `libyse.dll` and its runtime DLLs
next to `phi.exe` on every `flutter run` / `flutter build windows`.

To test against a local engine build instead, point `YSE_DLL_PATH` at the
directory holding its `libyse.dll` (and runtime DLLs) — it still takes
precedence over the bundled library:

```powershell
$env:YSE_DLL_PATH = "D:\path\to\yse-soundengine\build\bin"
```

## Develop

```powershell
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test integration_test
```

### Integration tests

`flutter test` only walks `test/`. The end-to-end suite lives in
`integration_test/`, needs a real device, and — on Windows — must be driven one
file per `flutter test` invocation: a single `flutter test integration_test`
run does not reliably carry the whole folder. Use the driver:

```powershell
pwsh tool/run_integration_tests.ps1                 # all files, one run each
pwsh tool/run_integration_tests.ps1 -Filter 'midi_*'  # just one surface
pwsh tool/run_integration_tests.ps1 -Shard 2 -Of 4    # the slice CI runs
```

It keeps going after a failure, prints the log of every file that failed, and
exits non-zero if any did. The suite injects `FakeYseGateway` throughout, so
the app under test never opens the engine.

CI runs the same script as a **post-merge sweep**: every push to `develop`
(i.e. every merged PR) triggers the full suite in the background, so a
regression is caught within ~20 minutes and — merges being sequential —
indicts exactly one PR. Feature PRs themselves stay cheap and skip the sweep;
locally, run only the integration files your change touches and leave the
full sweep to CI. Pre-merge coverage on demand: label a `develop` PR
`ci:integration` (worth it when the PR rewires the CI/e2e plumbing itself).
Release PRs into `main` always run the sweep pre-merge, and a nightly run
catches environment drift (runner image, toolchain) on days nothing merges.
See [.github/workflows/integration.yaml](.github/workflows/integration.yaml).

### Design tokens

`design system/colors_and_type.css` is the source of truth for the Dart token
files under `lib/design/tokens/`. After editing the CSS, regenerate:

```powershell
dart run tool/gen_tokens.dart           # rewrites the generated regions
dart run tool/gen_tokens.dart --check   # CI / pre-commit drift check
```

Each token file has a `// region: generated-from-css` block; the generator
only touches that block, leaving hand-maintained helpers (chrome heights,
BorderRadius shortcuts, font factory wrappers) intact. The `flutter test`
suite includes a drift guard that runs `--check`.

## Contributing

Everything is issue-driven — see [CLAUDE.md](CLAUDE.md) for the workflow rules.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
