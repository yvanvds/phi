import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_slug.dart';

/// The tutorial file-name rule (issue #489).
void main() {
  const known = ['.+', '~+', '.line', '~line', '~sine', '.metro', '.div', './'];

  test('a named type is its bare name', () {
    expect(TutorialSlug.of('.metro', knownTypes: known), 'metro');
    expect(TutorialSlug.of('~sine', knownTypes: known), 'sine');
  });

  test('operators are spelled out', () {
    expect(TutorialSlug.of('.!='), 'neq');
    expect(TutorialSlug.of('.+'), 'plus');
    expect(TutorialSlug.of('.||'), 'or');
    expect(TutorialSlug.of('.!-'), 'rminus');
    expect(TutorialSlug.of('./'), 'divide');
    expect(
      TutorialSlug.of('.div'),
      'div',
      reason: 'the word type keeps its name; ./ does not take it',
    );
  });

  test('a ~ type that clashes with a control type gets sig-', () {
    expect(TutorialSlug.of('~+', knownTypes: known), 'sig-plus');
    expect(TutorialSlug.of('~line', knownTypes: known), 'sig-line');
    expect(TutorialSlug.of('~sine', knownTypes: known), 'sine');
    expect(TutorialSlug.of('~+'), 'plus', reason: 'no catalogue, no clash');
  });

  test('anything else unsafe in a file name folds to -', () {
    expect(TutorialSlug.of('.array.at'), 'array-at');
    expect(TutorialSlug.of('.dict.pack'), 'dict-pack');
  });
}
