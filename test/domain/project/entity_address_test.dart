import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  group('construction', () {
    test('builds from kind and segments', () {
      final address = EntityAddress(
        kind: 'clip',
        segments: ['drums', 'intro_fill'],
      );
      expect(address.kind, 'clip');
      expect(address.segments, ['drums', 'intro_fill']);
      expect(address.name, 'intro_fill');
      expect(address.groupPath, ['drums']);
    });

    test('segments is unmodifiable', () {
      final address = EntityAddress(kind: 'clip', segments: ['a']);
      expect(() => address.segments.add('b'), throwsUnsupportedError);
    });

    test('rejects empty segments', () {
      expect(
        () => EntityAddress(kind: 'clip', segments: const []),
        throwsFormatException,
      );
    });

    test('rejects an invalid kind', () {
      expect(
        () => EntityAddress(kind: 'Clip', segments: ['a']),
        throwsFormatException,
      );
    });

    test('rejects an invalid segment', () {
      expect(
        () => EntityAddress(kind: 'clip', segments: ['a', 'B']),
        throwsFormatException,
      );
    });

    test('rejects a Python keyword segment', () {
      expect(
        () => EntityAddress(kind: 'clip', segments: ['class']),
        throwsFormatException,
      );
    });
  });

  group('parse / format', () {
    test('parses a dotted address', () {
      final address = EntityAddress.parse('clip.drums.intro_fill');
      expect(address.kind, 'clip');
      expect(address.segments, ['drums', 'intro_fill']);
    });

    test('round-trips through format', () {
      const dotted = 'mix.perc.snare';
      expect(EntityAddress.parse(dotted).format(), dotted);
      expect(EntityAddress.parse(dotted).toString(), dotted);
    });

    test('rejects a bare kind with no segment', () {
      expect(() => EntityAddress.parse('clip'), throwsFormatException);
    });

    test('rejects the empty string', () {
      expect(() => EntityAddress.parse(''), throwsFormatException);
    });

    test('rejects a doubled dot', () {
      expect(() => EntityAddress.parse('clip..intro'), throwsFormatException);
    });

    test('rejects a trailing dot', () {
      expect(() => EntityAddress.parse('clip.intro.'), throwsFormatException);
    });

    test('tryParse returns the address on success', () {
      expect(EntityAddress.tryParse('clip.intro'), isNotNull);
    });

    test('tryParse returns null on failure', () {
      expect(EntityAddress.tryParse('clip'), isNull);
      expect(EntityAddress.tryParse('clip.Intro'), isNull);
    });
  });

  group('navigation', () {
    test('top-level address', () {
      final address = EntityAddress.parse('clip.lead_line');
      expect(address.isTopLevel, isTrue);
      expect(address.groupPath, isEmpty);
      expect(address.parent, isNull);
    });

    test('nested parent', () {
      final address = EntityAddress.parse('clip.drums.intro_fill');
      expect(address.isTopLevel, isFalse);
      expect(address.parent, EntityAddress.parse('clip.drums'));
    });

    test('child appends a segment', () {
      final child = EntityAddress.parse('clip.drums').child('intro_fill');
      expect(child, EntityAddress.parse('clip.drums.intro_fill'));
    });

    test('child rejects an invalid segment', () {
      expect(
        () => EntityAddress.parse('clip.drums').child('Bad'),
        throwsFormatException,
      );
    });
  });

  group('isDescendantOf', () {
    final root = EntityAddress.parse('clip.drums');

    test('a deeper address is a descendant', () {
      expect(
        EntityAddress.parse('clip.drums.intro').isDescendantOf(root),
        isTrue,
      );
      expect(
        EntityAddress.parse('clip.drums.a.b').isDescendantOf(root),
        isTrue,
      );
    });

    test('a node is not a descendant of itself', () {
      expect(root.isDescendantOf(root), isFalse);
    });

    test('a sibling is not a descendant', () {
      expect(EntityAddress.parse('clip.bass').isDescendantOf(root), isFalse);
    });

    test('a different kind is never a descendant', () {
      expect(EntityAddress.parse('mix.drums.x').isDescendantOf(root), isFalse);
    });
  });

  group('equality', () {
    test('equal addresses are == with equal hashCodes', () {
      final a = EntityAddress.parse('clip.drums.intro');
      final b = EntityAddress(kind: 'clip', segments: ['drums', 'intro']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs by kind', () {
      expect(
        EntityAddress.parse('clip.a'),
        isNot(EntityAddress.parse('mix.a')),
      );
    });

    test('differs by segments', () {
      expect(
        EntityAddress.parse('clip.a.b'),
        isNot(EntityAddress.parse('clip.a.c')),
      );
    });

    test('order matters', () {
      expect(
        EntityAddress.parse('clip.a.b'),
        isNot(EntityAddress.parse('clip.b.a')),
      );
    });
  });
}
