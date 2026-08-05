import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_number_box.dart';

/// With no `NUMBER · F` header left to say so (issue #381), the **shape** is
/// what tells a number box from a message box: its top-right corner is cut
/// away. Asserted on the outline itself, which is the claim — a pixel
/// comparison would only be a slower way of asking the same question.
void main() {
  const size = Size(64, 24);

  group('outline', () {
    final path = PatchNumberBox.outlineFor(size);

    test('the top-right corner is cut away', () {
      expect(path.contains(const Offset(62, 2)), isFalse);
    });

    test('every other corner is inside the box', () {
      expect(path.contains(const Offset(2, 2)), isTrue);
      expect(path.contains(const Offset(2, 22)), isTrue);
      // The bottom right is square — only the top one is cut.
      expect(path.contains(const Offset(62, 22)), isTrue);
    });

    test('the cut scales with the box, so the shape survives any size', () {
      final tall = PatchNumberBox.outlineFor(const Size(64, 48));
      // Twice the height, twice the bite: a point that clears the cut on the
      // short box is inside it on the tall one.
      expect(path.contains(const Offset(48, 2)), isTrue);
      expect(tall.contains(const Offset(48, 2)), isFalse);
    });
  });

  testWidgets('the readout is kept clear of the cut corner', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: const PatchNumberBox(
              child: SizedBox(width: 1, height: 1, key: ValueKey('readout')),
            ),
          ),
        ),
      ),
    );

    final box = tester.getRect(find.byType(PatchNumberBox));
    final readout = tester.getRect(find.byKey(const ValueKey('readout')));

    // Ordinary padding on the left...
    expect(readout.left - box.left, PatchCanvasConstants.objectBoxPaddingH);
    // ...and more of it on the right, so a long value never runs into the cut.
    expect(
      box.right - readout.right,
      greaterThan(PatchCanvasConstants.objectBoxPaddingH),
    );
  });
}
