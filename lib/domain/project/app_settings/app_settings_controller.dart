import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'app_settings_store.dart';

/// The single live owner of the app-wide [AppSettings] value (design
/// `docs/design/settings-and-devices.md` §7).
///
/// Everything that changes a setting goes through this one object's [update]:
/// the project lifecycle controller folding in a recently-opened project, and
/// (later) the settings dialog editing the audio / MIDI / autosave-cadence
/// sections. Because it is the *only* thing that ever calls
/// [AppSettingsStore.save], two writers racing on `settings.json` are impossible
/// by construction — there is exactly one path to the file.
///
/// A [ChangeNotifier], like the other domain controllers, so the File menu
/// (recents) and the settings dialog rebuild when the live value changes. It is
/// injected wherever a setting is read or written, and tests drive it with the
/// in-memory [AppSettingsStore] fake.
class AppSettingsController extends ChangeNotifier {
  /// Binds the controller to its persistence [store] — the production
  /// `RealAppSettingsStore` or an in-memory fake in tests. The live value starts
  /// at defaults ([AppSettings.new]) until [load] reads the persisted file.
  AppSettingsController(this._store);

  final AppSettingsStore _store;

  AppSettings _value = const AppSettings();

  /// The current live settings — the single source of truth every reader shares.
  AppSettings get value => _value;

  /// Reads the persisted settings once at boot, replacing the live [value] and
  /// notifying. Intended to run exactly once before any [update]; call it during
  /// launch, before wiring readers that expect the on-disk value.
  Future<void> load() async {
    _value = await _store.load();
    notifyListeners();
  }

  /// Sets the live [value] to [next] and persists it immediately — settings
  /// writes are tiny (design §7). No-ops when [next] already equals the live
  /// value, so a redundant update neither writes the file nor notifies. The
  /// value and notification are applied synchronously; the returned future
  /// completes when the save lands, so a caller that must observe the write can
  /// await it (recents writes are fire-and-forget).
  Future<void> update(AppSettings next) async {
    if (next == _value) return;
    _value = next;
    notifyListeners();
    await _store.save(next);
  }
}
