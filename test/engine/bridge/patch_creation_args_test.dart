import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_creation_args.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';

/// The gate the inline object box runs before anything is created (issue #358):
/// a typed argument string checked against the type's documented
/// [PatchParamDescriptor]s, and resolved into the exact string to mint with.
///
/// Both halves matter for real reasons. The engine *crashes* when an object that
/// declares no parameters is handed any, and a value outside a documented range
/// silently misconfigures the object — so a refusal has to happen before the
/// native call, not after. And a name typed with no arguments still has to
/// arrive configured, which is what the positional default fill is for.
void main() {
  PatchParamDescriptor param(
    String name, {
    String defaultValue = '',
    String range = '',
  }) => PatchParamDescriptor(
    name: name,
    doc: '',
    defaultValue: defaultValue,
    range: range,
  );

  PatchObjectDescriptor desc(String type, List<PatchParamDescriptor> params) =>
      PatchObjectDescriptor(
        type: type,
        description: '',
        category: PatchObjectCategory.generic,
        isDsp: false,
        inlets: const [],
        outlets: const [],
        params: params,
      );

  final sine = desc('~sine', [
    param('frequency', defaultValue: '440', range: '0..20000'),
  ]);

  group('resolution', () {
    test('no typed arguments fall back to the documented defaults', () {
      final checked = PatchCreationArgs.check(sine, '');
      expect(checked.isValid, isTrue);
      expect(checked.args, '440');
    });

    test('a typed argument replaces its slot', () {
      expect(PatchCreationArgs.check(sine, '220').args, '220');
    });

    test('a short argument list keeps later slots at their defaults', () {
      final filter = desc('~lowpass', [
        param('cutoff', defaultValue: '1000', range: '0..20000'),
        param('q', defaultValue: '0.7', range: '0..10'),
      ]);
      // Positional: typing only the cutoff must not shift `q` into its slot.
      expect(PatchCreationArgs.check(filter, '400').args, '400 0.7');
    });

    test('runs of whitespace between arguments collapse', () {
      final filter = desc('~lowpass', [
        param('cutoff', defaultValue: '1000'),
        param('q', defaultValue: '0.7'),
      ]);
      expect(PatchCreationArgs.check(filter, '  400    2 ').args, '400 2');
    });

    test('a parameterless type resolves to the empty string', () {
      // `.slider` registers no parameters and crashes if handed any — it must
      // be created with nothing at all.
      final checked = PatchCreationArgs.check(desc('.slider', const []), '');
      expect(checked.isValid, isTrue);
      expect(checked.args, isEmpty);
    });
  });

  group('refusal', () {
    test('a parameterless type refuses any argument', () {
      final checked = PatchCreationArgs.check(desc('.slider', const []), '5');
      expect(checked.isValid, isFalse);
      expect(checked.problem, '.slider takes no arguments');
    });

    test('more arguments than parameters is refused', () {
      final checked = PatchCreationArgs.check(sine, '220 330');
      expect(checked.problem, '~sine takes at most 1 argument');
    });

    test('the count is pluralised', () {
      final two = desc('~lowpass', [
        param('cutoff', defaultValue: '1000'),
        param('q', defaultValue: '0.7'),
      ]);
      expect(
        PatchCreationArgs.check(two, '1 2 3').problem,
        '~lowpass takes at most 2 arguments',
      );
    });

    test('a non-number where a number is documented is refused', () {
      expect(
        PatchCreationArgs.check(sine, 'loud').problem,
        'frequency must be a number',
      );
    });

    test('a value outside the documented range is refused, either end', () {
      expect(
        PatchCreationArgs.check(sine, '-1').problem,
        'frequency must be in 0..20000',
      );
      expect(
        PatchCreationArgs.check(sine, '20001').problem,
        'frequency must be in 0..20000',
      );
    });

    test('the range bounds themselves are accepted', () {
      expect(PatchCreationArgs.check(sine, '0').isValid, isTrue);
      expect(PatchCreationArgs.check(sine, '20000').isValid, isTrue);
    });
  });

  group('what the metadata does not document is not invented', () {
    test('a parameter with a non-numeric default takes any word', () {
      final send = desc('.s', [param('name', defaultValue: 'bus')]);
      final checked = PatchCreationArgs.check(send, 'bells');
      expect(checked.isValid, isTrue);
      expect(checked.args, 'bells');
    });

    test('an undocumented default and range constrain nothing', () {
      final free = desc('.thing', [param('what')]);
      expect(PatchCreationArgs.check(free, 'anything').isValid, isTrue);
    });

    test('a prose range is not read as bounds', () {
      final note = desc('.note', [
        param('pitch', defaultValue: '60', range: 'midi note'),
      ]);
      // Still numeric (the default says so), but nothing to bound it by.
      expect(PatchCreationArgs.check(note, '9999').isValid, isTrue);
      expect(PatchCreationArgs.check(note, 'c4').problem, isNotNull);
    });

    test('a numeric range alone makes the parameter numeric', () {
      final gain = desc('.gain', [param('level', range: '0..1')]);
      expect(PatchCreationArgs.check(gain, 'loud').problem, isNotNull);
      expect(PatchCreationArgs.check(gain, '0.5').isValid, isTrue);
    });

    test('a negative range bound parses', () {
      final pan = desc('.pan', [
        param('pos', defaultValue: '0', range: '-1..1'),
      ]);
      expect(PatchCreationArgs.check(pan, '-1').isValid, isTrue);
      expect(PatchCreationArgs.check(pan, '-1.5').problem, isNotNull);
    });
  });
}
