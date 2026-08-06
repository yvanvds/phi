import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../../domain/project/store/asset_importer.dart';
import '../../domain/project/store/file_asset_importer.dart';
import 'rack_asset_source.dart';

/// Production [RackAssetSource] backed by `file_selector` + a [FileAssetImporter]
/// bound to the open project (design `docs/design/racks-and-voices.md` §4).
///
/// Filters the OS open dialog to the [RackAssetKind]'s extensions, then copies
/// the chosen file into the current project's `assets/` folder through the
/// importer the [directoryProvider] resolves for the live project location.
/// Constructing this touches no plugins — the method channel is only reached
/// when a dialog is actually opened — so it is safe as the surface's default in
/// headless tests. A `null` from [directoryProvider] (a never-saved project with
/// no `.phi` folder yet) skips the import and returns `null`.
class FileSelectorRackAssetSource implements RackAssetSource {
  /// Builds the source over a [_directoryProvider] that yields the open project's
  /// `.phi` folder path (or `null` before the project has a location).
  const FileSelectorRackAssetSource({required this._directoryProvider});

  final String? Function() _directoryProvider;

  @override
  Future<String?> pickAsset(RackAssetKind kind) async {
    final group = XTypeGroup(label: kind.name, extensions: kind.extensions);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    final directory = _directoryProvider();
    if (directory == null) return null;
    final importer = _importerFor(directory);
    return importer.import(file.path);
  }

  AssetImporter _importerFor(String directory) =>
      FileAssetImporter(Directory(directory));
}
