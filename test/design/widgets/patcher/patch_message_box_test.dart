import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_number_box.dart';

/// The `.m` object's **flag-shaped right edge** is what says "message" now that
/// no `MESSAGE` header does (issue #381): the edge is notched inwards to a
/// point, and the corners stay square — the opposite of a number box, which
/// keeps its edge and loses a corner.
void main() {
  const size = Size(96, 24);

  group('outline', () {
    final path = PatchMessageBox.outlineFor(size);

    test('the right edge is notched inwards at its middle', () {
      expect(path.contains(const Offset(94, 12)), isFalse);
      // ...and closes again well before the left side.
      expect(path.contains(const Offset(80, 12)), isTrue);
    });

    test('both right corners stay square', () {
      expect(path.contains(const Offset(94, 2)), isTrue);
      expect(path.contains(const Offset(94, 22)), isTrue);
    });

    test('it is not the shape a number box has', () {
      final number = PatchNumberBox.outlineFor(size);
      // The one point that separates them at a glance: the top-right corner is
      // there on a message and cut away on a number.
      const topRight = Offset(94, 2);
      expect(path.contains(topRight), isTrue);
      expect(number.contains(topRight), isFalse);
    });
  });

  testWidgets('the text is kept clear of the notch', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: const PatchMessageBox(
              child: SizedBox(width: 1, height: 1, key: ValueKey('message')),
            ),
          ),
        ),
      ),
    );

    final box = tester.getRect(find.byType(PatchMessageBox));
    final text = tester.getRect(find.byKey(const ValueKey('message')));

    expect(text.left - box.left, PatchCanvasConstants.objectBoxPaddingH);
    expect(
      box.right - text.right,
      greaterThan(PatchCanvasConstants.objectBoxPaddingH),
    );
  });
}
