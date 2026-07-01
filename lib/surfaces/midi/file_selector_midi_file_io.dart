import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'midi_file_io.dart';

/// Production [MidiFileIo] backed by the first-party `file_selector` plugin.
///
/// Filters to `.mid` / `.midi` files and, on save, writes the encoded bytes
/// to the location the user picked. Constructing this touches no plugins — the
/// method channel is only reached when a dialog is actually opened — so it is
/// safe as the viewport's default even in headless widget tests.
class FileSelectorMidiFileIo implements MidiFileIo {
  const FileSelectorMidiFileIo();

  static const _group = XTypeGroup(label: 'MIDI', extensions: ['mid', 'midi']);

  @override
  Future<Uint8List?> openSmf() async {
    final file = await openFile(acceptedTypeGroups: const [_group]);
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> saveSmf(String suggestedName, Uint8List bytes) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_group],
    );
    if (location == null) return false;
    final file = XFile.fromData(
      bytes,
      mimeType: 'audio/midi',
      name: suggestedName,
    );
    await file.saveTo(location.path);
    return true;
  }
}
