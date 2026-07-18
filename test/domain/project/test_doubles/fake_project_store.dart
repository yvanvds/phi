import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/store/entity_payload_codec.dart';
import 'package:phi/domain/project/store/project_serializer.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/project_store.dart';

/// In-memory [ProjectStore] for tests — the same Real/Fake split as
/// `FakeYseGateway`.
///
/// Backs the `.phi` folder onto a plain `path → contents` [files] map instead of
/// the disk, delegating every byte of format logic to [ProjectSerializer] (the
/// very code `RealProjectStore` runs), so a save/load round-trip is exercised
/// without touching the filesystem. [saveCount] lets tests assert autosave
/// cadence, and [files] is exposed so a test can inspect the exact bytes written.
class FakeProjectStore implements ProjectStore {
  /// Builds a fake store. [codecs] supplies per-kind payload (de)serialisers and
  /// [groupPayloadKinds] the kinds whose groups persist a payload (issue #165),
  /// mirroring `RealProjectStore`.
  FakeProjectStore({
    Map<String, EntityPayloadCodec> codecs = const {},
    Set<String> groupPayloadKinds = const {},
  }) : _serializer = ProjectSerializer(
         codecs: codecs,
         groupPayloadKinds: groupPayloadKinds,
       );

  /// The in-memory folder: relative path → pretty-printed JSON contents.
  final Map<String, String> files = {};

  /// How many times [save] has been called — handy for autosave assertions.
  int saveCount = 0;

  final ProjectSerializer _serializer;

  @override
  Future<bool> exists() async =>
      files.containsKey(ProjectSerializer.manifestPath);

  @override
  Future<void> save(
    ProjectSnapshot snapshot, {
    Set<EntityAddress>? dirty,
  }) async {
    saveCount++;
    final plan = _serializer.planSave(
      snapshot,
      dirty: dirty,
      existingFiles: files.keys.toSet(),
    );
    files.addAll(plan.writes);
    for (final path in plan.deletes) {
      files.remove(path);
    }
  }

  @override
  Future<ProjectSnapshot> load() async =>
      _serializer.readSnapshot(Map.of(files));
}
