import 'patch_tutorial_source.dart';

/// A [PatchTutorialSource] over an in-memory path → text map — for tests and
/// for any host that ships no asset bundle (issue #489).
class MemoryPatchTutorialSource implements PatchTutorialSource {
  const MemoryPatchTutorialSource(this.files);

  /// Asset path → file text.
  final Map<String, String> files;

  @override
  Future<String?> read(String path) async => files[path];
}
