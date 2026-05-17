# Phi

A flexible workstation for live electronic music performance. Personal,
single-developer, years-long project — not a product. Public so others can
read along.

The vision: polytemporal, spatially-aware electronic music shaped in real time,
on a substrate where no layer is master. See **[phi-vision.md](phi-vision.md)**
for the full design intent, and **[PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md)**
for the current architectural snapshot.

## Status

**Phase 1 — audio hello-world.** A Flutter (Windows) shell renders the Phi
design system, and a single button in the Mix surface arms the engine's
built-in audio test signal via the dart-yse FFI bridge. Six surfaces are
planned (Scene · Patcher · Code · State · MIDI · Mix); only Mix has a stub.

## Stack

- **Engine:** [yse-soundengine](https://github.com/yvanvds/yse-soundengine) (C++).
- **FFI bridge:** [dart-yse](https://github.com/yvanvds/dart-yse) — package name `yse`.
- **UI:** Flutter ≥ 3.38, Windows desktop only for now.
- **Design system:** [`design system/`](design%20system/) — colors, type, motion,
  components. Source-of-truth for the Dart token files under `lib/design/tokens/`.

## Build

Requires Windows, [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.38,
and the `yse-soundengine` build toolchain (MSYS2 Clang64 + CMake).

```powershell
# 1. Clone phi and dart-yse as siblings.
cd D:\
git clone https://github.com/yvanvds/dart-yse
git clone https://github.com/yvanvds/phi

# 2. Build libyse.dll once (see dart-yse README for the full recipe).
cd D:\dart-yse
git submodule update --init --recursive
cmake -S third_party\yse-soundengine -B third_party\yse-soundengine\build -G Ninja `
      -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
      -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/c++.exe
cmake --build third_party\yse-soundengine\build --target yse

# 3. Point YSE_DLL_PATH at the libyse.dll directory.
$env:YSE_DLL_PATH = "D:\dart-yse\third_party\yse-soundengine\build\bin"

# 4. Resolve deps and run.
cd D:\phi
flutter pub get
flutter run -d windows
```

## Develop

```powershell
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test integration_test
```

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
