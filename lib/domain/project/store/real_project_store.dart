import 'dart:io';

import 'package:path/path.dart' as p;

import '../entity_address.dart';
import 'entity_payload_codec.dart';
import 'project_serializer.dart';
import 'project_snapshot.dart';
import 'project_store.dart';

/// The production [ProjectStore]: it reads and writes an actual `.phi` folder
/// through `dart:io` (design `docs/design/project-registry.md` §8 — `dart:io` is
/// fine in this non-Flutter layer).
///
/// All format logic lives in [ProjectSerializer]; this class only turns the
/// serializer's plan into file writes/deletes and lists the folder back for a
/// load. Relative paths from the serializer are POSIX-style (`/`-separated) and
/// joined onto [directory] with the platform separator here, so the same format
/// works on Windows and elsewhere.
class RealProjectStore implements ProjectStore {
  /// Binds the store to the project [directory] (the `<name>.phi` folder).
  /// [codecs] supplies per-kind payload (de)serialisers; [groupPayloadKinds]
  /// names the kinds whose groups persist a payload in `_group.json` (issue
  /// #165).
  RealProjectStore(
    this.directory, {
    Map<String, EntityPayloadCodec> codecs = const {},
    Set<String> groupPayloadKinds = const {},
  }) : _serializer = ProjectSerializer(
         codecs: codecs,
         groupPayloadKinds: groupPayloadKinds,
       );

  /// The `.phi` folder this store reads and writes.
  final Directory directory;

  final ProjectSerializer _serializer;

  @override
  Future<bool> exists() =>
      File(_absolute(ProjectSerializer.manifestPath)).exists();

  @override
  Future<void> save(
    ProjectSnapshot snapshot, {
    Set<EntityAddress>? dirty,
  }) async {
    final plan = _serializer.planSave(
      snapshot,
      dirty: dirty,
      existingFiles: await _listJsonFiles(),
    );
    for (final dir in plan.ensureDirs) {
      await Directory(_absolute(dir)).create(recursive: true);
    }
    for (final entry in plan.writes.entries) {
      final file = File(_absolute(entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    for (final relative in plan.deletes) {
      final file = File(_absolute(relative));
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<ProjectSnapshot> load() async =>
      _serializer.readSnapshot(await _readJsonFiles());

  Future<Set<String>> _listJsonFiles() async {
    final result = <String>{};
    if (!await directory.exists()) return result;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.json')) {
        result.add(_relative(entity.path));
      }
    }
    return result;
  }

  Future<Map<String, String>> _readJsonFiles() async {
    final result = <String, String>{};
    if (!await directory.exists()) return result;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.json')) {
        result[_relative(entity.path)] = await entity.readAsString();
      }
    }
    return result;
  }

  String _absolute(String relative) =>
      p.joinAll([directory.path, ...relative.split('/')]);

  String _relative(String absolute) =>
      p.split(p.relative(absolute, from: directory.path)).join('/');
}
