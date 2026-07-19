import 'dart:io';

import 'package:path/path.dart' as p;

import 'asset_importer.dart';
import 'project_serializer.dart';

/// The production [AssetImporter]: copies imported binaries into the project's
/// `assets/` folder through `dart:io` (design `docs/design/project-registry.md`
/// §8 — `dart:io` is fine in this non-Flutter layer).
///
/// Bound to one project [directory] (the `<name>.phi` folder). The returned
/// reference is always POSIX-style (`/`-separated) so it matches the refs the
/// serializer writes and resolves the same on every platform.
class FileAssetImporter implements AssetImporter {
  /// Binds the importer to the project [directory] whose `assets/` folder
  /// receives the copies.
  FileAssetImporter(this.directory);

  /// The `.phi` folder this importer copies into.
  final Directory directory;

  @override
  Future<String> import(String sourcePath) async {
    final assetsDirPath = p.join(directory.path, ProjectSerializer.assetsDir);
    final source = File(sourcePath);

    // Already inside the project's assets/? Return the existing relative ref
    // without copying — a re-import of a project-owned asset is a no-op.
    final absoluteSource = p.normalize(source.absolute.path);
    if (p.isWithin(assetsDirPath, absoluteSource)) {
      return _relative(p.basename(absoluteSource));
    }

    final bytes = await source.readAsBytes();
    await Directory(assetsDirPath).create(recursive: true);

    final base = p.basename(sourcePath);
    final stem = p.basenameWithoutExtension(base);
    final ext = p.extension(base);

    var name = base;
    var attempt = 0;
    while (true) {
      final target = File(p.join(assetsDirPath, name));
      if (!await target.exists()) {
        await target.writeAsBytes(bytes);
        return _relative(name);
      }
      // A file with this name already exists: reuse it when the bytes match,
      // otherwise pick the next free `stem-N.ext`.
      if (_sameBytes(await target.readAsBytes(), bytes)) {
        return _relative(name);
      }
      attempt++;
      name = '$stem-$attempt$ext';
    }
  }

  String _relative(String name) =>
      p.posix.join(ProjectSerializer.assetsDir, name);

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
