import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/completion/phi_completion_item_kind.dart';
import 'package:phi/domain/code/completion/phi_completion_resolver.dart';
import 'package:phi/domain/code/completion/phi_method_table.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/voice/voice_definition.dart';

void main() {
  late ProjectRegistry registry;
  late PhiCompletionResolver resolver;

  void voice(String name, String color) => registry.createEntity(
    EntityAddress.parse('voice.$name'),
    payload: <String, Object?>{
      'kind': 'internal',
      'synth': 'synth.sine',
      'output': 'mix.master',
      'color': color,
    },
  );

  void clip(String path, int bars) => registry.createEntity(
    EntityAddress.parse('clip.$path'),
    payload: <String, Object?>{
      'source': <String, Object?>{'bars': bars, 'beatsPerBar': 4, 'notes': []},
    },
  );

  setUp(() {
    registry = ProjectRegistry();
    resolver = PhiCompletionResolver(registry);
    // Two voices, a top-level clip, a nested clip group, and one entity in each
    // remaining namespace so every namespace can trigger.
    voice('bells', 'voice3');
    voice('pad', 'voice5');
    clip('phrase_a', 4);
    clip('drums.intro', 8); // auto-creates the clip.drums group
    clip('drums.fill', 2);
    registry.createEntity(EntityAddress.parse('mix.main'));
    registry.createEntity(EntityAddress.parse('fx.reverb'));
    registry.createEntity(EntityAddress.parse('patch.swirl'));
    registry.createEntity(EntityAddress.parse('domain.drum'));
    registry.createEntity(EntityAddress.parse('var.section'));
    registry.createEntity(EntityAddress.parse('state.verse'));
  });

  tearDown(() => registry.dispose());

  List<String> words(String before) =>
      resolver.resolve(before)!.items.map((i) => i.identifier).toList();

  group('namespace popup', () {
    test('voice. lists its entities from the registry', () {
      final result = resolver.resolve('voice.')!;
      expect(result.input, '');
      expect(words('voice.'), ['bells', 'pad']);
      expect(
        result.items.every((i) => i.kind == PhiCompletionItemKind.entity),
        isTrue,
      );
    });

    test('every phi namespace triggers a popup', () {
      for (final ns in PhiCompletionResolver.namespaces) {
        expect(
          resolver.resolve('$ns.'),
          isNotNull,
          reason: '"$ns." should pop a completion',
        );
      }
    });

    test('a leading expression before the namespace still triggers', () {
      expect(words('pad = voice.'), ['bells', 'pad']);
    });

    test('a partial identifier narrows and is reported as input', () {
      final result = resolver.resolve('voice.pa')!;
      expect(result.input, 'pa');
      expect(result.items.single.identifier, 'pad');
    });

    test('voice entities carry their colour token from the payload', () {
      final bells = resolver
          .resolve('voice.')!
          .items
          .firstWhere((i) => i.identifier == 'bells');
      expect(bells.colorToken, 'voice3');
      expect(bells.namespace, 'voice');
    });

    test('a typed VoiceDefinition payload also yields the colour token', () {
      registry.createEntity(
        EntityAddress.parse('voice.lead'),
        payload: VoiceDefinition.internal(
          synth: EntityAddress.parse('synth.sine'),
          output: EntityAddress.parse('mix.master'),
          color: 'voice2',
        ),
      );
      final lead = resolver
          .resolve('voice.')!
          .items
          .firstWhere((i) => i.identifier == 'lead');
      expect(lead.colorToken, 'voice2');
    });

    test(
      'clip entities carry their bar length; groups are marked as groups',
      () {
        final items = resolver.resolve('clip.')!.items;
        final phrase = items.firstWhere((i) => i.identifier == 'phrase_a');
        expect(phrase.kind, PhiCompletionItemKind.entity);
        expect(phrase.bars, 4);
        final drums = items.firstWhere((i) => i.identifier == 'drums');
        expect(drums.kind, PhiCompletionItemKind.group);
        expect(drums.bars, isNull);
      },
    );
  });

  group('group narrowing', () {
    test('clip.drums. lists the group members', () {
      expect(words('clip.drums.'), ['intro', 'fill']);
    });

    test('a partial narrows within the group', () {
      expect(words('clip.drums.in'), ['intro']);
    });
  });

  group('method table (one level past an entity)', () {
    test('voice.bells. offers the full static method table', () {
      final result = resolver.resolve('voice.bells.')!;
      expect(result.input, '');
      expect(words('voice.bells.'), phiMethodTable);
      expect(
        result.items.every((i) => i.kind == PhiCompletionItemKind.method),
        isTrue,
      );
    });

    test('a partial narrows the method table', () {
      expect(words('voice.bells.no'), ['note']);
    });

    test('a deeper nested clip entity also offers the method table', () {
      expect(words('clip.drums.intro.'), phiMethodTable);
    });
  });

  group('no popup in plain contexts', () {
    test('a bare identifier with no dot', () {
      expect(resolver.resolve('gain'), isNull);
    });

    test('a plain function call', () {
      expect(resolver.resolve('print('), isNull);
    });

    test('a dotted chain rooted outside a phi namespace', () {
      expect(resolver.resolve('foo.'), isNull);
      expect(resolver.resolve('myvoice.'), isNull);
    });

    test('an empty segment in the chain', () {
      expect(resolver.resolve('voice..'), isNull);
    });

    test('a namespace with no matching entity', () {
      expect(resolver.resolve('voice.zz'), isNull);
    });

    test('an empty namespace pops nothing', () {
      final empty = ProjectRegistry();
      addTearDown(empty.dispose);
      expect(PhiCompletionResolver(empty).resolve('voice.'), isNull);
    });

    test('a path that resolves to nothing', () {
      expect(resolver.resolve('clip.nope.'), isNull);
    });
  });
}
