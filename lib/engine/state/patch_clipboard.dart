import 'patch_clipboard_data.dart';

/// The patcher's copy buffer (issue #435) — what `Ctrl+C` fills and `Ctrl+V`
/// pastes from.
///
/// A plain mutable holder, deliberately **not** the OS clipboard: the payload
/// is live gesture vocabulary ([PatchClipboardData]), not text, and nothing
/// outside Phi could paste it. One instance is shared across every editor a
/// [PatchLibraryController] binds, so a fragment copied in one patch pastes
/// into another; a standalone [PatcherController] owns its own.
///
/// It also counts the pastes taken from the current copy ([takePasteStep]), so
/// repeated `Ctrl+V` lands each generation one grid step further instead of
/// stacking every copy on the same spot. A fresh [set] resets the count.
class PatchClipboard {
  PatchClipboardData? _data;
  int _pastes = 0;

  /// The last copied fragment, or null when nothing was copied yet.
  PatchClipboardData? get data => _data;

  /// Replace the buffer with a fresh copy and reset the paste generation.
  void set(PatchClipboardData data) {
    _data = data;
    _pastes = 0;
  }

  /// Claim the next paste generation: 1 for the first paste of the current
  /// copy, 2 for the second, … — the multiple of the grid step that paste
  /// offsets the fragment by.
  int takePasteStep() => ++_pastes;
}
