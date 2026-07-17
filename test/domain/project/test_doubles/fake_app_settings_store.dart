import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_store.dart';

/// In-memory [AppSettingsStore] for tests — the same Real/Fake split as
/// `FakeProjectStore`.
///
/// Holds the settings in a field so a test can seed a starting value (recents,
/// autosave cadence) and inspect what the controller wrote back. [saveCount]
/// lets a test assert persistence happened.
class FakeAppSettingsStore implements AppSettingsStore {
  FakeAppSettingsStore([AppSettings initial = const AppSettings()])
    : _settings = initial;

  AppSettings _settings;

  /// How many times [save] has been called.
  int saveCount = 0;

  /// The most recently saved (or seeded) settings.
  AppSettings get current => _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    saveCount++;
  }
}
