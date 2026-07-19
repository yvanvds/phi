import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/sample_recipe.dart';

void main() {
  group('SampleRecipe', () {
    test('round-trips through JSON', () {
      const recipe = SampleRecipe(
        file: 'assets/kick.wav',
        root: 36,
        low: 24,
        high: 48,
        attack: 0.002,
        release: 0.4,
      );
      expect(SampleRecipe.fromJson(recipe.toJson()), recipe);
    });

    test('fromJson requires a file path', () {
      expect(
        () => SampleRecipe.fromJson(const {'root': 60}),
        throwsFormatException,
      );
    });

    test('fromJson fills defaults for the other fields', () {
      final recipe = SampleRecipe.fromJson(const {'file': 'assets/snare.wav'});
      expect(recipe, const SampleRecipe(file: 'assets/snare.wav'));
    });

    test('copyWith replaces only the given fields', () {
      const recipe = SampleRecipe(file: 'a.wav');
      expect(recipe.copyWith(root: 72).root, 72);
      expect(recipe.copyWith(root: 72).file, 'a.wav');
    });

    test('equality is by value', () {
      expect(
        const SampleRecipe(file: 'a.wav'),
        const SampleRecipe(file: 'a.wav'),
      );
      expect(
        const SampleRecipe(file: 'a.wav'),
        isNot(const SampleRecipe(file: 'b.wav')),
      );
    });
  });
}
