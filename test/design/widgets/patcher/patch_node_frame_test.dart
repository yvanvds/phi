import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';

/// The frame draws its port dots on the **horizontal** edges since issue #377:
/// inlets straddling the top edge, outlets straddling the bottom one, each
/// centred on the offset the caller supplies.
void main() {
  const frameSize = Size(160, 64);

  Future<void> pumpFrame(
    WidgetTester tester, {
    required List<double> inputXs,
    required List<double> outputXs,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: frameSize,
            child: PatchNodeFrame(
              title: 'fan',
              voice: 1,
              armed: false,
              inputPortXs: inputXs,
              outputPortXs: outputXs,
              inputVoices: [for (final _ in inputXs) 1],
              outputVoices: [for (final _ in outputXs) 1],
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('inlets straddle the top edge and outlets the bottom one', (
    tester,
  ) async {
    await pumpFrame(tester, inputXs: const [16, 42], outputXs: const [16]);

    final frame = tester.getRect(find.byType(PatchNodeFrame));
    final dots = tester
        .widgetList<PatchPortDot>(find.byType(PatchPortDot))
        .toList();
    expect(dots, hasLength(3));

    final centres = [
      for (var i = 0; i < dots.length; i++)
        tester.getCenter(find.byType(PatchPortDot).at(i)),
    ];

    // Two inlets on the top edge, at the x offsets asked for.
    expect(centres[0], Offset(frame.left + 16, frame.top));
    expect(centres[1], Offset(frame.left + 42, frame.top));
    // The outlet on the bottom edge, at the same x as the first inlet — so a
    // cable leaves this box and arrives at the next one on the same axis.
    expect(centres[2], Offset(frame.left + 16, frame.bottom));
  });

  testWidgets('the dot is centred on the edge, half in and half out', (
    tester,
  ) async {
    await pumpFrame(tester, inputXs: const [16], outputXs: const []);

    final frame = tester.getRect(find.byType(PatchNodeFrame));
    final dot = tester.getRect(find.byType(PatchPortDot));

    expect(dot.height, PatchCanvasConstants.portDotSize);
    expect(dot.top, frame.top - PatchCanvasConstants.portDotRadius);
    expect(dot.bottom, frame.top + PatchCanvasConstants.portDotRadius);
  });

  testWidgets('a node with no ports draws no dots at all', (tester) async {
    await pumpFrame(tester, inputXs: const [], outputXs: const []);
    expect(find.byType(PatchPortDot), findsNothing);
  });
}
