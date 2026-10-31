import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/per_user_folders.dart';

import 'app_settings.dart';
import 'app_settings_store.dart';

/// The production [AppSettingsStore]: it reads and writes `settings.json` under
/// the app's settings folder through `dart:io` (design
/// `docs/design/project-registry.md` §5 — `dart:io` is fine in this non-Flutter
/// layer).
///
/// The folder comes from [PerUserFolders]: `%APPDATA%/phi/` on Windows,
/// `$XDG_CONFIG_HOME/phi/` (default `~/.config/phi/`) on Linux. The [directory]
/// can be overridden for tests that want a real temp folder.
class RealAppSettingsStore implements AppSettingsStore {
  /// Binds the store to a settings [directory], defaulting to the platform's
  /// per-user app-data folder ([defaultDirectory]).
  RealAppSettingsStore({Directory? directory})
    : directory = directory ?? defaultDirectory();

  /// The folder holding `settings.json`.
  final Directory directory;

  /// The settings file's name inside [directory].
  static const String fileName = 'settings.json';

  /// The default per-user settings folder for the running platform — see
  /// [PerUserFolders.settingsDirectory].
  static Directory defaultDirectory() =>
      Directory(PerUserFolders.host().settingsDirectory());

  File get _file => File(p.join(directory.path, fileName));

  @override
  Future<AppSettings> load() async {
    final file = _file;
    if (!await file.exists()) return const AppSettings();
    return _decode(await file.readAsString());
  }

  /// Same fallbacks as [load] — a missing, unreadable or corrupt file yields
  /// the defaults rather than bricking launch.
  @override
  AppSettings loadSync() {
    final file = _file;
    try {
      if (!file.existsSync()) return const AppSettings();
      return _decode(file.readAsStringSync());
    } on FileSystemException {
      return const AppSettings();
    }
  }

  AppSettings _decode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return const AppSettings();
      return AppSettings.fromJson(decoded);
    } on FormatException {
      // A corrupt settings file must not brick launch — fall back to defaults.
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await directory.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString('${encoder.convert(settings.toJson())}\n');
  }
}
