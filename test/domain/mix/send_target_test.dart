import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/mix/send_target.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';

/// A send may only target a top-level `mix.` return bus (design
/// `docs/design/mix.md` §4) — the domain refuses anything else at edit time.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late ProjectRegistry registry;

  setUp(() => registry = ProjectRegistry());
  tearDown(() => registry.dispose());

  group('SendTarget.isReturn', () {
    test('accepts a top-level return bus', () {
      registry.createEntity(
        addr('mix.verb'),
        payload: const MixStrip(voice: 1, isReturn: true).toJson(),
      );
      expect(SendTarget.isReturn(registry, addr('mix.verb')), isTrue);
    });

    test('rejects a plain (non-return) strip', () {
      registry.createEntity(
        addr('mix.drums'),
        payload: const MixStrip(voice: 1).toJson(),
      );
      expect(SendTarget.isReturn(registry, addr('mix.drums')), isFalse);
    });

    test('rejects a group bus even when its payload is a return', () {
      // Returns live outside the tree, so a group is never a valid target.
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'voice': 1, 'return': true},
      );
      expect(SendTarget.isReturn(registry, addr('mix.drums')), isFalse);
    });

    test('rejects a nested (non-top-level) address', () {
      registry.createEntity(
        addr('mix.drums.kick'),
        payload: const MixStrip(voice: 1, isReturn: true).toJson(),
      );
      expect(SendTarget.isReturn(registry, addr('mix.drums.kick')), isFalse);
    });

    test('rejects a missing address', () {
      expect(SendTarget.isReturn(registry, addr('mix.absent')), isFalse);
    });

    test('rejects a non-mix entity', () {
      registry.createEntity(addr('clip.phrase_a'));
      expect(SendTarget.isReturn(registry, addr('clip.phrase_a')), isFalse);
    });
  });

  group('SendTarget.validate', () {
    test('returns normally for a return bus', () {
      registry.createEntity(
        addr('mix.verb'),
        payload: const MixStrip(voice: 1, isReturn: true).toJson(),
      );
      expect(
        () => SendTarget.validate(registry, addr('mix.verb')),
        returnsNormally,
      );
    });

    test('throws ArgumentError for a non-return target', () {
      registry.createEntity(
        addr('mix.drums'),
        payload: const MixStrip(voice: 1).toJson(),
      );
      expect(
        () => SendTarget.validate(registry, addr('mix.drums')),
        throwsArgumentError,
      );
    });
  });
}
