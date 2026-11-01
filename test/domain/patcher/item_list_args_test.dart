import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/item_list_args.dart';

/// [ItemListArgs] mirrors the engine's `gItemListBase::ShapeItems`
/// (issue #471).
void main() {
  group('parse', () {
    test('no items is two, named by their index', () {
      final a = ItemListArgs.parse('');
      expect(a.multi, isFalse);
      expect(a.labels, ['0', '1']);
    });

    test('item names, one per word', () {
      final a = ItemListArgs.parse('sine  square saw');
      expect(a.labels, ['sine', 'square', 'saw']);
      expect(a.count, 3);
    });

    test('a single number of at least 1 is a count', () {
      expect(ItemListArgs.parse('4').labels, ['0', '1', '2', '3']);
      expect(ItemListArgs.parse('2.7').labels, ['0', '1']);
      expect(ItemListArgs.parse('1000').count, ItemListArgs.maxItems);
    });

    test('a single 0, or a single name, is one item', () {
      expect(ItemListArgs.parse('0').labels, ['0']);
      expect(ItemListArgs.parse('5abc').labels, ['5abc']);
    });

    test('a leading multi is the mode, not an item', () {
      final a = ItemListArgs.parse('multi 3');
      expect(a.multi, isTrue);
      expect(a.labels, ['0', '1', '2']);
      expect(ItemListArgs.parse('multi').labels, ['0', '1']);
      expect(ItemListArgs.parse('a multi').multi, isFalse);
    });

    test('item names past the ceiling are dropped', () {
      final many = List.generate(300, (i) => 'i$i').join(' ');
      expect(ItemListArgs.parse(many).count, ItemListArgs.maxItems);
    });
  });

  group('selectionOf', () {
    test('single select reads the index', () {
      final a = ItemListArgs.parse('a b c');
      expect(a.selectionOf('2'), {2});
      expect(a.selectionOf('0'), {0});
      expect(a.selectionOf('5'), isEmpty, reason: 'past the end');
      expect(a.selectionOf(''), isEmpty);
    });

    test('multi select reads one flag per item', () {
      final a = ItemListArgs.parse('multi a b c');
      expect(a.selectionOf('0 1 1'), {1, 2});
      expect(a.selectionOf('0 0 0'), isEmpty);
      expect(a.selectionOf('1 0 0 1'), {0}, reason: 'flags past the end');
    });
  });
}
