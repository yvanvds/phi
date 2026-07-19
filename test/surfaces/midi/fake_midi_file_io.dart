import 'dart:typed_data';

import 'package:phi/surfaces/midi/midi_file_io.dart';

/// Test double for [MidiFileIo]: [openSmf] returns preset [openBytes] under
/// [openName] (as if the user picked a file) and [saveSmf] captures what was
/// written, so tests can drive the real import/export flow without native
/// dialogs.
class FakeMidiFileIo implements MidiFileIo {
  FakeMidiFileIo({this.openBytes, this.openName = 'imported.mid'});

  /// Bytes handed back from [openSmf]; `null` simulates a cancelled dialog.
  Uint8List? openBytes;

  /// The filename [openSmf] reports the picked file under — the import slugs a
  /// new clip entity's name from it (issue #191).
  String openName;

  /// Captured from the most recent [saveSmf] call.
  Uint8List? savedBytes;
  String? savedName;

  int openCalls = 0;
  int saveCalls = 0;

  @override
  Future<PickedMidiFile?> openSmf() async {
    openCalls++;
    final bytes = openBytes;
    if (bytes == null) return null;
    return (bytes: bytes, name: openName);
  }

  @override
  Future<bool> saveSmf(String suggestedName, Uint8List bytes) async {
    saveCalls++;
    savedName = suggestedName;
    savedBytes = bytes;
    return true;
  }
}
