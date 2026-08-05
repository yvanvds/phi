import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_type_name.dart';
import 'package:yse/yse.dart';

/// The one rule every surface reads the `~`/`.` prefix by now that none of them
/// draws it (issue #380): what the bare name is, and which domain the id names.
void main() {
  group('bare', () {
    test('strips the DSP and control prefixes', () {
      expect(PatchTypeName.bare(Obj.dSine), 'sine');
      expect(PatchTypeName.bare(Obj.gMetro), 'metro');
      expect(PatchTypeName.bare(Obj.dDac), 'dac');
    });

    test('the arithmetic pairs collide, which is the whole difficulty', () {
      // Four pairs share a bare name — colour separates them on screen, and the
      // completion list separates them while typing.
      expect(PatchTypeName.bare(Obj.dMultiply), '*');
      expect(PatchTypeName.bare(Obj.gMultiply), '*');
      expect(PatchTypeName.bare(Obj.dAdd), PatchTypeName.bare(Obj.gAdd));
    });

    test('an unprefixed id comes back untouched', () {
      expect(PatchTypeName.bare(Obj.patcher), 'patcher');
      expect(PatchTypeName.bare(''), '');
    });

    test('a lone prefix keeps its character rather than baring to nothing', () {
      // Not a type, but a name that renders as an empty box would be worse than
      // one that renders as the glyph typed.
      expect(PatchTypeName.bare('~'), '~');
      expect(PatchTypeName.bare('.'), '.');
    });
  });

  group('isDsp', () {
    test('the `~` prefix is what says audio rate', () {
      expect(PatchTypeName.isDsp(Obj.dSine), isTrue);
      expect(PatchTypeName.isDsp(Obj.dMultiply), isTrue);
      expect(PatchTypeName.isDsp(Obj.gMetro), isFalse);
      expect(PatchTypeName.isDsp(Obj.gMultiply), isFalse);
      expect(PatchTypeName.isDsp(Obj.patcher), isFalse);
      expect(PatchTypeName.isDsp(''), isFalse);
    });
  });
}
