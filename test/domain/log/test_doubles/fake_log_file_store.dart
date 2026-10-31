import 'package:phi/domain/log/log_file_store.dart';

/// An in-memory [LogFileStore] mirroring the real one's contract: session names
/// come back newest-first, the marker is a single nullable slot.
class FakeLogFileStore implements LogFileStore {
  final Map<String, StringBuffer> files = {};
  String? marker;

  @override
  Future<List<String>> sessionLogNames() async {
    final names = files.keys.toList()..sort((a, b) => b.compareTo(a));
    return names;
  }

  @override
  Future<void> appendLine(String name, String line) async {
    (files[name] ??= StringBuffer()).writeln(line);
  }

  @override
  Future<void> deleteSessionLog(String name) async {
    files.remove(name);
  }

  @override
  Future<bool> markerExists() async => marker != null;

  @override
  Future<void> writeMarker(String note) async {
    marker = note;
  }

  @override
  Future<void> deleteMarker() async {
    marker = null;
  }
}
