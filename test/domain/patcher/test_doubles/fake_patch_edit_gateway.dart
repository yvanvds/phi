import 'package:phi/domain/patcher/patch_connection.dart';
import 'package:phi/domain/patcher/patch_edit_gateway.dart';
import 'package:phi/domain/patcher/patch_object_spec.dart';
import 'package:phi/domain/patcher/patch_point.dart';

/// In-memory [PatchEditGateway] for the gesture-command tests — a stand-in for
/// the live engine patcher (the real, FFI-backed implementation lands with the
/// gateway generalisation, epic issue 2).
///
/// It holds exactly the minimal state the gestures touch — objects keyed by
/// handle id and a flat cable list — so a command's `apply`/`revert` can be
/// asserted against a concrete before/after picture. Mirrors the Real/Fake seam
/// split every other gateway uses (`FakePatcherGateway`, `FakeYseGateway`, …).
class FakePatchEditGateway implements PatchEditGateway {
  final Map<int, PatchObjectSpec> _objects = {};
  final List<PatchConnection> _cables = [];
  int _nextId = 1;

  /// The live objects, keyed by handle id — a defensive copy.
  Map<int, PatchObjectSpec> get objects => Map.unmodifiable(_objects);

  /// The live cables — a defensive copy.
  List<PatchConnection> get cables => List.unmodifiable(_cables);

  @override
  int createObject(PatchObjectSpec spec) {
    final id = _nextId++;
    _objects[id] = spec;
    return id;
  }

  @override
  void restoreObject(int id, PatchObjectSpec spec) {
    _objects[id] = spec;
    if (id >= _nextId) _nextId = id + 1;
  }

  @override
  void removeObject(int id) {
    _objects.remove(id);
    _cables.removeWhere((c) => c.fromId == id || c.toId == id);
  }

  @override
  PatchObjectSpec describe(int id) {
    final spec = _objects[id];
    if (spec == null) {
      throw StateError('describe: no object with id $id');
    }
    return spec;
  }

  @override
  List<PatchConnection> connectionsOf(int id) =>
      _cables.where((c) => c.fromId == id || c.toId == id).toList();

  @override
  void connect(PatchConnection connection) => _cables.add(connection);

  @override
  void disconnect(PatchConnection connection) =>
      _cables.removeWhere((c) => c == connection);

  @override
  void moveObject(int id, PatchPoint position) {
    _objects[id] = describe(id).copyWith(position: position);
  }

  @override
  PatchPoint positionOf(int id) => describe(id).position;

  @override
  void setParam(int id, String name, double value) {
    final spec = describe(id);
    _objects[id] = spec.copyWith(params: {...spec.params, name: value});
  }

  @override
  double? paramOf(int id, String name) => _objects[id]?.params[name];

  @override
  void clearParam(int id, String name) {
    final spec = describe(id);
    _objects[id] = spec.copyWith(params: {...spec.params}..remove(name));
  }
}
