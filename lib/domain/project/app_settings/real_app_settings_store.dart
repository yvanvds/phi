import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_settings.dart';
import 'app_settings_store.dart';

/// The production [AppSettingsStore]: it reads and writes `settings.json` under
/// the app's settings folder through `dart:io` (design
/// `docs/design/project-registry.md` §5 — `dart:io` is fine in this non-Flutter
/// layer).
///
/// On Windows the folder is `%APPDATA%/phi/`; elsewhere it falls back to
/// `$HOME/.phi/` (or the current directory as a last resort) so the same code
/// runs under a Linux CI without a real `%APPDATA%`. The [directory] can be
/// overridden for tests that want a real temp folder.
class RealAppSettingsStore implements AppSettingsStore {
  /// Binds the store to a settings [directory], defaulting to the platform's
  /// per-user app-data folder ([defaultDirectory]).
  RealAppSettingsStore({Directory? directory})
    : directory = directory ?? defaultDirectory();

  /// The folder holding `settings.json`.
  final Directory directory;

  /// The settings file's name inside [directory].
  static const String fileName = 'settings.json';

  /// The default per-user settings folder: `%APPDATA%/phi/` on Windows, else
  /// `$HOME/.phi/`, else `./.phi/`.
  static Directory defaultDirectory() {
    final env = Platform.environment;
    final base =
        env['APPDATA'] ??
        env['HOME'] ??
        env['USERPROFILE'] ??
        Directory.current.path;
    return Directory(p.join(base, 'phi'));
  }

  File get _file => File(p.join(directory.path, fileName));

  @override
  Future<AppSettings> load() async {
    final file = _file;
    if (!await file.exists()) return const AppSettings();
    return _decode(await file.readAsString());
  }

  /// A synchronous [load], for the one read that must happen before the engine
  /// starts: the stored sample rate, which the engine can only take at init
  /// (issue #443). Same fallbacks as [load] — a missing, unreadable or corrupt
  /// file yields the defaults rather than bricking launch.
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
