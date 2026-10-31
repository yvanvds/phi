import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/per_user_folders.dart';

import 'log_file_store.dart';

/// The production [LogFileStore]: session logs and the clean-shutdown marker on
/// the real filesystem, in the per-user logs folder (design
/// `docs/design/diagnostics.md` §2, §6, §8 decision 1 — per-machine diagnostics).
///
/// The folder comes from [PerUserFolders]: `%APPDATA%/phi/logs/` on Windows,
/// `$XDG_STATE_HOME/phi/logs/` (default `~/.local/state/phi/logs/`) on Linux.
/// The [directory] can be overridden for tests that want a real temp folder.
class RealLogFileStore implements LogFileStore {
  /// Binds the store to a logs [directory], defaulting to [defaultDirectory].
  RealLogFileStore({Directory? directory})
    : directory = directory ?? defaultDirectory();

  /// The folder holding the session logs and the marker.
  final Directory directory;

  /// The clean-shutdown marker's file name — no `.log` suffix, so it is never
  /// mistaken for a session file.
  static const String markerFileName = 'clean-shutdown.marker';

  /// The default per-user logs folder for the running platform — see
  /// [PerUserFolders.logsDirectory].
  static Directory defaultDirectory() =>
      Directory(PerUserFolders.host().logsDirectory());

  bool _isSessionLog(String name) =>
      name.startsWith('phi-') && name.endsWith('.log');

  File _file(String name) => File(p.join(directory.path, name));

  File get _marker => File(p.join(directory.path, markerFileName));

  @override
  Future<List<String>> sessionLogNames() async {
    if (!await directory.exists()) return const [];
    final names = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (_isSessionLog(name)) names.add(name);
    }
    // The stamp is zero-padded and sortable, so descending string order is
    // newest-first.
    names.sort((a, b) => b.compareTo(a));
    return names;
  }

  @override
  Future<void> appendLine(String name, String line) async {
    await directory.create(recursive: true);
    await _file(name).writeAsString('$line\n', mode: FileMode.append);
  }

  @override
  Future<void> deleteSessionLog(String name) async {
    final file = _file(name);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> markerExists() => _marker.exists();

  @override
  Future<void> writeMarker(String note) async {
    await directory.create(recursive: true);
    await _marker.writeAsString('$note\n');
  }

  @override
  Future<void> deleteMarker() async {
    if (await _marker.exists()) await _marker.delete();
  }
}
