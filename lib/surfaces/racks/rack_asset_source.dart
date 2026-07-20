/// The kind of asset an [RackAssetSource] pick is filtering for — an FM sysex
/// bank, an SFZ instrument, or a raw audio sample (design
/// `docs/design/racks-and-voices.md` §4).
enum RackAssetKind {
  /// A DX7 `.syx` bank for the FM editor's bank picker.
  fmBank(<String>['syx']),

  /// An `.sfz` instrument (and, on disk, its neighbouring samples) for the
  /// sampler editor.
  sfz(<String>['sfz']),

  /// A single audio sample (`.wav` / `.flac` / …) for the sampler's
  /// single-sample recipe.
  sample(<String>['wav', 'flac', 'aiff', 'aif', 'ogg']);

  const RackAssetKind(this.extensions);

  /// The file extensions (no leading dot) the OS picker filters to.
  final List<String> extensions;
}

/// Picks an outside asset file and copies it into the open project's `assets/`
/// folder, handing back the **project-relative** ref a synth definition stores
/// (design `docs/design/racks-and-voices.md` §4 — assets are copied in on import
/// so the `.phi` folder stays portable).
///
/// Injected into the Racks surface so the FM / sampler editors drive the real
/// import flow behind a fake in tests — the native file dialog and the
/// filesystem copy are the un-fakeable OS surface. The production
/// implementation ([FileSelectorRackAssetSource]) composes `file_selector` with
/// the project's [AssetImporter]; the returned ref is what the editor writes
/// into the definition payload.
abstract interface class RackAssetSource {
  /// Prompt for a file of [kind], copy it into the project's `assets/` folder,
  /// and return its project-relative ref (e.g. `assets/rhodes.syx`). Returns
  /// `null` when the user cancels the dialog or no project location is open yet
  /// (nothing to import into).
  Future<String?> pickAsset(RackAssetKind kind);
}
