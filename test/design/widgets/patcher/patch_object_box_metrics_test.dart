import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_object_box_metrics.dart';

/// How big an object box has to be (issue #379, design §7): as wide as its
/// text, floored by the minimum width its port count demands (#377), capped
/// past which the line ellipsises — and one text line plus padding tall,
/// whatever the ports.
void main() {
  const chromeH =
      2 *
      (PatchCanvasConstants.objectBoxPaddingH +
          PatchCanvasConstants.nodeBorderWidth);

  test('the box is as wide as its text needs', () {
    final short = PatchObjectBoxMetrics.sizeFor(
      text: '~dac',
      inputs: 0,
      outputs: 0,
    );
    final long = PatchObjectBoxMetrics.sizeFor(
      text: '~sine 440.5 with more to say',
      inputs: 0,
      outputs: 0,
    );

    expect(long.width, greaterThan(short.width));
    // Text plus its two paddings and two borders — nothing else in there.
    expect(short.width, greaterThan(chromeH));
  });

  test('the port count sets a width floor a short line cannot undercut', () {
    final bare = PatchObjectBoxMetrics.sizeFor(
      text: '.t',
      inputs: 0,
      outputs: 0,
    );
    final ported = PatchObjectBoxMetrics.sizeFor(
      text: '.t',
      inputs: 4,
      outputs: 1,
    );

    expect(ported.width, PatchCanvasConstants.minWidthForPorts(4));
    expect(ported.width, greaterThan(bare.width));
  });

  test('the busier edge wins the floor', () {
    final inlets = PatchObjectBoxMetrics.sizeFor(
      text: '.t',
      inputs: 5,
      outputs: 1,
    );
    final outlets = PatchObjectBoxMetrics.sizeFor(
      text: '.t',
      inputs: 1,
      outputs: 5,
    );

    expect(inlets.width, outlets.width);
    expect(inlets.width, PatchCanvasConstants.minWidthForPorts(5));
  });

  test('a very long line stops growing at the cap and ellipsises instead', () {
    final huge = PatchObjectBoxMetrics.sizeFor(
      text: '.metro ${'1234567890 ' * 40}',
      inputs: 0,
      outputs: 0,
    );

    expect(huge.width, PatchCanvasConstants.objectBoxMaxWidth);
  });

  test('the port floor outranks the cap — dots never hang off the edges', () {
    // A box narrower than its own ports would draw them outside itself, so the
    // text is what gives way.
    const count = 20;
    final crowded = PatchObjectBoxMetrics.sizeFor(
      text: '.t',
      inputs: count,
      outputs: 0,
    );

    expect(
      PatchCanvasConstants.minWidthForPorts(count),
      greaterThan(PatchCanvasConstants.objectBoxMaxWidth),
      reason: 'the fixture only tests anything if the floor exceeds the cap',
    );
    expect(crowded.width, PatchCanvasConstants.minWidthForPorts(count));
  });

  test('height is one text line plus padding, whatever the ports', () {
    final none = PatchObjectBoxMetrics.sizeFor(
      text: '~dac',
      inputs: 0,
      outputs: 0,
    );
    final many = PatchObjectBoxMetrics.sizeFor(
      text: '~dac',
      inputs: 6,
      outputs: 6,
    );

    // The whole point of moving ports onto the horizontal edges (#377): the
    // count buys width, never height.
    expect(many.height, none.height);
    // And a one-line box is well under the two-row node it replaces.
    expect(none.height, lessThan(2 * PatchCanvasConstants.headerHeight));
  });

  test('a longer line does not make a taller box', () {
    final short = PatchObjectBoxMetrics.sizeFor(
      text: '.t',
      inputs: 0,
      outputs: 0,
    );
    final long = PatchObjectBoxMetrics.sizeFor(
      text: '.metro ${'1234567890 ' * 40}',
      inputs: 0,
      outputs: 0,
    );

    expect(long.height, short.height);
  });
}
