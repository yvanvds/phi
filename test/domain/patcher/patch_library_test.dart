import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_library.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';

/// Unit coverage for the pure-domain `patch.` command factory (issue #224).
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late ProjectRegistry registry;
  late PatchLibrary library;

  setUp(() {
    registry = ProjectRegistry();
    library = PatchLibrary(registry);
  });

  tearDown(() => registry.dispose());

  test('newPatch builds a create command for an empty patch', () {
    final command = library.newPatch();
    command.apply();

    expect(command.address, patch('patch'));
    final payload = PatchPayload.fromJson(
      (registry.entityAt(patch('patch'))!.payload! as Map).cast(),
    );
    expect(payload.dump, isEmpty);
    expect(payload.placement, isNull);
  });

  test('newPatch makes the name unique among siblings', () {
    library.newPatch().apply();
    library.newPatch().apply();

    expect(registry.contains(patch('patch')), isTrue);
    expect(registry.contains(patch('patch_2')), isTrue);
  });

  test('duplicate copies the whole payload beside the original', () {
    registry.createEntity(
      patch('src'),
      payload: PatchPayload(
        dump: const {'objects': 2},
        placement: mix('reverb'),
      ).toJson(),
    );

    final command = library.duplicate(patch('src'));
    command.apply();

    expect(command.address, patch('src_copy'));
    final payload = PatchPayload.fromJson(
      (registry.entityAt(patch('src_copy'))!.payload! as Map).cast(),
    );
    expect(payload.dump, const {'objects': 2});
    expect(payload.placement, mix('reverb'));
  });

  test('duplicate throws when no patch entity sits at the source', () {
    expect(() => library.duplicate(patch('ghost')), throwsArgumentError);
  });
}
