import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';

/// The tutorial index (issue #489): type → slug, several types per slug.
void main() {
  final catalog = TutorialCatalog.fromJson({
    '.metro': 'metro',
    '.umenu': 'menus',
    '.radiogroup': 'menus',
    '.tab': 'menus',
    '~+': 'sig-plus',
    '.broken': 42,
    '.blank': '  ',
  });

  test('hasTutorial / tutorialFor answer by canonical type id', () {
    expect(catalog.hasTutorial('.metro'), isTrue);
    expect(catalog.tutorialFor('.metro'), 'metro');
    expect(catalog.tutorialFor('~+'), 'sig-plus');
    expect(catalog.hasTutorial('metro'), isFalse, reason: 'bare is not an id');
    expect(catalog.hasTutorial('.sine'), isFalse);
    expect(catalog.tutorialFor('.sine'), isNull);
  });

  test('one tutorial may cover several types', () {
    expect(catalog.typesFor('menus'), ['.umenu', '.radiogroup', '.tab']);
    expect(catalog.slugs, {'metro', 'menus', 'sig-plus'});
  });

  test('entries that are not a non-empty string are skipped', () {
    expect(catalog.hasTutorial('.broken'), isFalse);
    expect(catalog.hasTutorial('.blank'), isFalse);
    expect(catalog.types, hasLength(5));
  });

  test('the empty catalog has nothing', () {
    expect(TutorialCatalog.empty.isEmpty, isTrue);
    expect(TutorialCatalog.empty.hasTutorial('.metro'), isFalse);
  });

  test('asset paths live under assets/tutorials/patcher', () {
    expect(TutorialCatalog.indexPath, 'assets/tutorials/patcher/index.json');
    expect(
      TutorialCatalog.assetPathFor('metro'),
      'assets/tutorials/patcher/metro.phitut.json',
    );
  });
}
