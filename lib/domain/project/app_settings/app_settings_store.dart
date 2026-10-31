import 'app_settings.dart';

/// The persistence seam for [AppSettings] — the same Real/Fake split as
/// `ProjectStore` and `YseGateway`.
///
/// `RealAppSettingsStore` (`dart:io`) reads and writes the per-user `settings.json`;
/// an in-memory fake keeps the same value for tests. Callers (the project
/// lifecycle controller) depend on this interface, never on the filesystem.
abstract interface class AppSettingsStore {
  /// Reads the settings, returning defaults ([AppSettings.new]) when no file has
  /// been written yet.
  Future<AppSettings> load();

  /// A synchronous [load], with the same fallbacks, for the one read that must
  /// happen before the engine starts: the stored audio device and rate, which
  /// the engine boots straight onto (issues #443, #449).
  AppSettings loadSync();

  /// Persists [settings], creating the settings folder if needed.
  Future<void> save(AppSettings settings);
}
