import 'app_settings.dart';

/// The persistence seam for [AppSettings] — the same Real/Fake split as
/// `ProjectStore` and `YseGateway`.
///
/// `RealAppSettingsStore` (`dart:io`) reads and writes `%APPDATA%/phi/settings.json`;
/// an in-memory fake keeps the same value for tests. Callers (the project
/// lifecycle controller) depend on this interface, never on the filesystem.
abstract interface class AppSettingsStore {
  /// Reads the settings, returning defaults ([AppSettings.new]) when no file has
  /// been written yet.
  Future<AppSettings> load();

  /// Persists [settings], creating the settings folder if needed.
  Future<void> save(AppSettings settings);
}
