/// Copies an imported binary asset into a project's `assets/` folder and hands
/// back a **project-relative** reference (design `docs/design/racks-and-voices.md`
/// §4; `docs/design/project-registry.md` §5).
///
/// A synth or fx definition references its assets — `.syx` FM banks, `.sfz`
/// instruments and their samples, wavetables — by a relative path so the whole
/// project stays portable: move the `.phi` folder and every reference still
/// resolves. Importing an outside file therefore *copies it in* first and stores
/// only the relative ref.
///
/// The same Real/Fake split as [ProjectStore]: [FileAssetImporter] copies through
/// `dart:io`; a fake records the imports for tests and the racks import UI
/// (issues #210/#211). The returned path is POSIX-style (`/`-separated), matching
/// the refs the serializer writes, and is what a definition stores.
abstract interface class AssetImporter {
  /// Copy the file at [sourcePath] into the project's `assets/` folder and
  /// return its project-relative path (e.g. `assets/rhodes.syx`).
  ///
  /// Re-importing is cheap and stable: a source already inside the project's
  /// `assets/` folder is returned as-is, and a byte-identical file already
  /// present reuses the existing copy rather than duplicating it. A basename
  /// collision with *different* bytes is uniquified (`rhodes-1.syx`). Throws if
  /// [sourcePath] cannot be read.
  Future<String> import(String sourcePath);
}
