import 'dart:typed_data';

/// Abstraction over the native open/save file dialogs used by the MIDI
/// surface's SMF import/export affordances.
///
/// Injected into the viewport so tests can drive the real import/export flow
/// with a fake that returns canned bytes and captures written bytes — the
/// native dialogs themselves are an un-fakeable OS surface. The byte↔clip
/// translation lives in the pure-Dart SMF codec (`lib/domain/midi/smf/`); this
/// interface only owns the disk round-trip.
abstract interface class MidiFileIo {
  /// Prompt for a `.mid` file and return its bytes, or `null` if the user
  /// cancelled the dialog.
  Future<Uint8List?> openSmf();

  /// Prompt for a save location (seeded with [suggestedName]) and write
  /// [bytes] there. Returns `true` if the file was written, `false` if the
  /// user cancelled.
  Future<bool> saveSmf(String suggestedName, Uint8List bytes);
}
