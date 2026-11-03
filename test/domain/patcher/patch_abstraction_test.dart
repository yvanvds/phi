import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_abstraction.dart';
import 'package:phi/domain/patcher/patch_object_types.dart';
import 'package:phi/domain/project/entity_address.dart';

/// The rule that makes a subpatch box an instance of an abstraction (#553).
void main() {
  EntityAddress at(String dotted) => EntityAddress.parse(dotted);

  group('referenceIn', () {
    test('reads a patch address', () {
      expect(PatchAbstraction.referenceIn('patch.gain'), at('patch.gain'));
      expect(
        PatchAbstraction.referenceIn('  patch.fx.gain '),
        at('patch.fx.gain'),
      );
    });

    test('leaves an ordinary name alone', () {
      for (final name in ['', 'gain', 'my gain', 'patch', 'patch.', 'mix.a']) {
        expect(PatchAbstraction.referenceIn(name), isNull, reason: name);
      }
      expect(PatchAbstraction.referenceIn('patch.gain two'), isNull);
    });
  });

  test('no engine type id reads as a definition', () {
    for (final type in PatchObjectTypes.all) {
      expect(PatchAbstraction.addressOfType(type), isNull, reason: type);
    }
  });

  test('a definition is offered under its address', () {
    final type = PatchAbstraction.typeOf(at('patch.fx.gain'));
    expect(PatchAbstraction.addressOfType(type), at('patch.fx.gain'));
  });

  group('moved', () {
    test('follows a rename', () {
      expect(
        PatchAbstraction.moved(
          at('patch.gain'),
          at('patch.gain'),
          at('patch.level'),
        ),
        at('patch.level'),
      );
    });

    test('follows a group around it', () {
      expect(
        PatchAbstraction.moved(
          at('patch.fx.deep.gain'),
          at('patch.fx'),
          at('patch.effects'),
        ),
        at('patch.effects.deep.gain'),
      );
    });

    test('leaves anything else', () {
      expect(
        PatchAbstraction.moved(
          at('patch.other'),
          at('patch.gain'),
          at('patch.level'),
        ),
        at('patch.other'),
      );
    });
  });
}
