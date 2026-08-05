import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patch_gui_poller.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the **gate** on the patcher's live-value refresh (issue
/// #357).
///
/// The refresh itself is a timer, and this is a live-performance instrument: a
/// patcher on a background tab, or one holding nothing that displays an engine
/// value, must schedule no work whatever. These pin all three gates by counting
/// the asks the poller actually makes.
void main() {
  late FakePatcherGateway gateway;
  late _CountingController controller;

  /// Long enough for several [PatchGuiPoller.period]s to come due.
  const window = Duration(milliseconds: 200);

  NodeDescriptor desc(String type, {bool readsGuiValue = false}) =>
      NodeDescriptor(
        type: type,
        defaultSize: const Size(120, 80),
        defaultArgs: '',
        inputs: const [],
        outputs: const [],
        buildBody: (ctx, node, controller) => const SizedBox.shrink(),
        readsGuiValue: readsGuiValue,
      );

  void addNode(String type, {bool readsGuiValue = false}) {
    final d = desc(type, readsGuiValue: readsGuiValue);
    NodeTypeRegistry.instance.register(d);
    controller.addNode(desc: d, position: Offset.zero);
  }

  Future<void> pumpPoller(WidgetTester tester, {required bool active}) =>
      tester.pumpWidget(
        PatchGuiPoller(
          controller: controller,
          active: active,
          child: const SizedBox.shrink(),
        ),
      );

  setUp(() {
    gateway = FakePatcherGateway();
    controller = _CountingController(gateway);
    NodeTypeRegistry.instance.clear();
  });

  tearDown(() {
    controller.dispose();
    NodeTypeRegistry.instance.clear();
  });

  testWidgets('polls while the surface is showing a patch with live bodies', (
    tester,
  ) async {
    addNode(Obj.gSlider, readsGuiValue: true);
    await pumpPoller(tester, active: true);

    await tester.pump(window);
    expect(controller.refreshes, greaterThan(1));
  });

  testWidgets('a patcher nobody is looking at polls nothing', (tester) async {
    addNode(Obj.gSlider, readsGuiValue: true);
    await pumpPoller(tester, active: false);

    await tester.pump(window);
    expect(controller.refreshes, 0);
  });

  testWidgets('the poll starts and stops as the surface comes and goes', (
    tester,
  ) async {
    addNode(Obj.gSlider, readsGuiValue: true);
    await pumpPoller(tester, active: false);
    await tester.pump(window);
    expect(controller.refreshes, 0);

    // Switching to the patcher tab wakes it...
    await pumpPoller(tester, active: true);
    await tester.pump(window);
    final whileShowing = controller.refreshes;
    expect(whileShowing, greaterThan(1));

    // ...and switching away parks it again, rather than leaving a timer running
    // behind a surface nobody can see.
    await pumpPoller(tester, active: false);
    await tester.pump(window);
    expect(controller.refreshes, whileShowing);
  });

  testWidgets('a patch with nothing that displays an engine value is not '
      'polled', (tester) async {
    // `.b` bangs and `.m` renders its creation args — neither can change from
    // underneath, so there is nothing here to ask about.
    addNode(Obj.gButton);
    addNode(Obj.gMessage);
    await pumpPoller(tester, active: true);

    await tester.pump(window);
    expect(controller.refreshes, 0);
  });

  testWidgets('the poll follows the first live body into the patch and the '
      'last one out', (tester) async {
    await pumpPoller(tester, active: true);
    await tester.pump(window);
    expect(controller.refreshes, 0);

    // Drop a slider on the canvas: now there is something to watch.
    addNode(Obj.gSlider, readsGuiValue: true);
    await tester.pump(window);
    expect(controller.refreshes, greaterThan(1));

    // Delete it again and the patch goes quiet.
    final after = controller.refreshes;
    controller.removeNode(controller.graph.nodes.first.id);
    await tester.pump(window);
    expect(controller.refreshes, after);
  });

  testWidgets('an unmounted poller leaves no timer behind', (tester) async {
    addNode(Obj.gSlider, readsGuiValue: true);
    await pumpPoller(tester, active: true);
    await tester.pump(window);
    final before = controller.refreshes;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(window);

    expect(controller.refreshes, before);
  });
}

/// A controller that counts the asks made of it, so a test can tell a parked
/// poll from a running one without reaching into the widget's timer.
class _CountingController extends PatcherController {
  _CountingController(super.gateway);

  int refreshes = 0;

  @override
  int refreshGuiValues() {
    refreshes++;
    return super.refreshGuiValues();
  }
}
