import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/project/store/file_asset_importer.dart';

void main() {
  late Directory projectDir;
  late Directory sourceDir;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('phi_project_');
    sourceDir = Directory.systemTemp.createTempSync('phi_source_');
  });

  tearDown(() {
    if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  File writeSource(String name, List<int> bytes) {
    final f = File(p.join(sourceDir.path, name));
    f.writeAsBytesSync(bytes);
    return f;
  }

  test(
    'copies an outside file into assets/ and returns a relative ref',
    () async {
      final source = writeSource('rhodes.syx', [1, 2, 3, 4]);
      final importer = FileAssetImporter(projectDir);

      final ref = await importer.import(source.path);

      expect(ref, 'assets/rhodes.syx');
      final copied = File(p.join(projectDir.path, 'assets', 'rhodes.syx'));
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsBytesSync(), [1, 2, 3, 4]);
    },
  );

  test('returns a POSIX-style ref even on Windows', () async {
    final source = writeSource('bells.syx', [9]);
    final ref = await FileAssetImporter(projectDir).import(source.path);
    expect(ref.contains('\\'), isFalse);
    expect(ref, 'assets/bells.syx');
  });

  test('re-importing identical bytes reuses the existing copy', () async {
    final source = writeSource('kick.wav', [5, 5, 5]);
    final importer = FileAssetImporter(projectDir);

    final first = await importer.import(source.path);
    final second = await importer.import(source.path);

    expect(second, first);
    final assets = Directory(p.join(projectDir.path, 'assets')).listSync();
    expect(assets, hasLength(1), reason: 'no duplicate on identical re-import');
  });

  test('uniquifies a basename collision with different bytes', () async {
    final importer = FileAssetImporter(projectDir);
    final a = writeSource('patch.syx', [1, 1]);
    final firstRef = await importer.import(a.path);

    // A different file that happens to share the basename.
    final b = File(p.join(sourceDir.path, 'nested_patch.syx'))
      ..writeAsBytesSync([2, 2]);
    // Rename to collide on basename.
    final collide = File(p.join(sourceDir.path, 'patch.syx'));
    collide.writeAsBytesSync([2, 2]);
    b.deleteSync();
    final secondRef = await importer.import(collide.path);

    expect(firstRef, 'assets/patch.syx');
    expect(secondRef, 'assets/patch-1.syx');
    final assets = Directory(p.join(projectDir.path, 'assets')).listSync();
    expect(assets, hasLength(2));
  });

  test(
    'a source already inside assets/ is returned as-is, not re-copied',
    () async {
      final assetsDir = Directory(p.join(projectDir.path, 'assets'))
        ..createSync(recursive: true);
      final inside = File(p.join(assetsDir.path, 'owned.syx'))
        ..writeAsBytesSync([7]);

      final ref = await FileAssetImporter(projectDir).import(inside.path);

      expect(ref, 'assets/owned.syx');
      expect(assetsDir.listSync(), hasLength(1));
    },
  );

  test('preserves the extension when uniquifying', () async {
    final importer = FileAssetImporter(projectDir);
    writeSource('loop.wav', [1]);
    await importer.import(p.join(sourceDir.path, 'loop.wav'));
    // Overwrite the source with different bytes, same name.
    writeSource('loop.wav', [2]);
    final ref = await importer.import(p.join(sourceDir.path, 'loop.wav'));
    expect(ref, 'assets/loop-1.wav');
  });
}
