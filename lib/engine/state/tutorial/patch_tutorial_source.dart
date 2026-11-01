/// Where the patcher's bundled tutorials are read from (issue #489).
///
/// The production [BundlePatchTutorialSource] reads the Flutter asset bundle;
/// tests hand in an in-memory source so a widget test can open a tutorial
/// written in the fake gateway's dump format.
abstract interface class PatchTutorialSource {
  /// The raw text of the asset at [path] (`assets/tutorials/patcher/…`), or
  /// null when there is no such asset.
  Future<String?> read(String path);
}
