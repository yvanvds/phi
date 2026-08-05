import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_gui_object.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';

/// A GUI object is **its own control and nothing else** (design §7, §12.2,
/// issue #381): the seat this widget provides adds no frame, no header band and
/// no padding, and the only chrome it contributes is the ports — inlets
/// straddling the top edge, outlets straddling the bottom one (issue #377),
/// which is the one thing a bare control cannot carry itself.
///
/// Replaces the coverage of the retired `PatchNodeFrame`, whose port geometry
/// this inherits verbatim.
void main() {
  const nodeSize = Size(160, 64);

  Future<void> pump(
    WidgetTester tester, {
    required List<double> inputXs,
    required List<double> outputXs,
    Widget child = const SizedBox.expand(),
    bool armed = false,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: nodeSize,
            child: PatchGuiObject(
              voice: 1,
              armed: armed,
              inputPortXs: inputXs,
              outputPortXs: outputXs,
              inputVoices: [for (final _ in inputXs) 1],
              outputVoices: [for (final _ in outputXs) 1],
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('inlets straddle the top edge and outlets the bottom one', (
    tester,
  ) async {
    await pump(tester, inputXs: const [16, 42], outputXs: const [16]);

    final node = tester.getRect(find.byType(PatchGuiObject));
    expect(find.byType(PatchPortDot), findsNWidgets(3));

    final centres = [
      for (var i = 0; i < 3; i++)
        tester.getCenter(find.byType(PatchPortDot).at(i)),
    ];

    expect(centres[0], Offset(node.left + 16, node.top));
    expect(centres[1], Offset(node.left + 42, node.top));
    // The outlet at the same x as the first inlet — so a cable leaves this
    // control and arrives at the next one on the same axis.
    expect(centres[2], Offset(node.left + 16, node.bottom));
  });

  testWidgets('the dot is centred on the edge, half in and half out', (
    tester,
  ) async {
    await pump(tester, inputXs: const [16], outputXs: const []);

    final node = tester.getRect(find.byType(PatchGuiObject));
    final dot = tester.getRect(find.byType(PatchPortDot));

    expect(dot.height, PatchCanvasConstants.portDotSize);
    expect(dot.top, node.top - PatchCanvasConstants.portDotRadius);
    expect(dot.bottom, node.top + PatchCanvasConstants.portDotRadius);
  });

  testWidgets('a node with no ports draws no dots at all', (tester) async {
    await pump(tester, inputXs: const [], outputXs: const []);
    expect(find.byType(PatchPortDot), findsNothing);
  });

  testWidgets('the control fills the node — no frame, no header, no padding', (
    tester,
  ) async {
    await pump(
      tester,
      inputXs: const [16],
      outputXs: const [16],
      child: const SizedBox.expand(key: ValueKey('control')),
    );

    // The whole rectangle the canvas laid out is the control's. What used to
    // sit around it — a 22px uppercase title band and 8px of body padding — is
    // gone, so the two rects coincide exactly.
    expect(
      tester.getRect(find.byKey(const ValueKey('control'))),
      tester.getRect(find.byType(PatchGuiObject)),
    );
    // ...and nothing captions it.
    expect(find.byType(Text), findsNothing);
  });
}
