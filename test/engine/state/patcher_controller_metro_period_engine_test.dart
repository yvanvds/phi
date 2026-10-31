import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

/// Regression for issue #438: re-typing a **running** metro's argument in its
/// object box changes the rate it ticks at, against the real engine.
///
/// The edit enters exactly where the canvas hands an Enter over —
/// [PatcherController.applyBoxEdit] — and runs the whole production path
/// (`SetPatchParamsCommand` → `setNodeParams` → [RealPatcherGateway.setParams]
/// → yse `setParams`). The canvas → `applyBoxEdit` leg is driven through the
/// real app by `integration_test/patcher_edit_object_box_test.dart`; what a
/// fake gateway cannot show, and what this pins, is the engine actually
/// retiming a timer that is already running (yvanvds/yse-soundengine#625,
/// fixed in libYSE v3.1.0 bundled by yse 0.2.0).
///
/// The ticks are counted where they leave the patch: the metro drives a `.s`
/// slot of a named patcher, read back on the bus. The patch is **started**
/// (mounted as a source, what the placement bar's start does through
/// `PatchReconciler.start`): the engine applies a live `setParams` at the top
/// of the patcher's next audio block, so only a rendering patcher picks the
/// edit up. The session is offline, so the test pumps it itself —
/// `renderOffline` runs that block and `update()` delivers the timer thread's
/// publishes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var engineUp = false;

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
  });

  tearDownAll(() {
    if (engineUp) System.instance.close();
  });

  /// Pump the offline session for [span] and return how many bangs arrived
  /// on [ticks] meanwhile.
  Future<int> countTicks(List<Object> ticks, Duration span) async {
    final start = ticks.length;
    final clock = Stopwatch()..start();
    while (clock.elapsed < span) {
      System.instance.renderOffline(1);
      System.instance.update();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    System.instance.update();
    return ticks.length - start;
  }

  test(
    'a running metro whose argument is edited ticks at the new rate',
    () async {
      final gateway = RealPatcherGateway();
      final controller = PatcherController(gateway, name: 'phi438');
      addTearDown(() {
        controller
          ..unmountAudio()
          ..dispose();
        gateway.disposeAll();
      });

      final catalogue = {for (final d in gateway.objectTypes()) d.type: d};
      final PatchObjectDescriptor metroDesc = catalogue[Obj.gMetro]!;

      final metro = controller.createObject(
        desc: metroDesc,
        position: Offset.zero,
        args: '200',
      )!;
      final PatchNodeId send = controller.createObject(
        desc: catalogue[Obj.gSend]!,
        position: const Offset(0, 80),
        args: 'tick',
      )!;
      expect(
        controller.connect(
          PatchPortId(nodeId: metro, side: PatchPortSide.output, index: 0),
          PatchPortId(nodeId: send, side: PatchPortSide.input, index: 0),
        ),
        isTrue,
      );

      final ticks = <Object>[];
      final sub = Bus.subscribe('patcher.phi438.tick')
          .listen((f) => ticks.add(f.value));
      addTearDown(sub.cancel);

      // A patcher only mounts once it has a `~dac` (an empty one crashes the
      // audio thread), so give it one, as any sounding patch has.
      controller.createObject(
        desc: catalogue[Obj.dDac]!,
        position: const Offset(0, 160),
      );

      // Start the patch as a source, then the metro inside it, and let it
      // settle into its 200 ms beat.
      controller.mountAudio();
      controller.setControlInt(metro, inlet: 0, value: 1);
      await countTicks(ticks, const Duration(milliseconds: 250));
      final slow = await countTicks(ticks, const Duration(milliseconds: 1000));

      // The user re-types the box: `metro 200` → `metro 40`, metro still on.
      controller.applyBoxEdit(metro, desc: metroDesc, args: '40');
      expect(controller.argsOf(metro), '40');
      // The live param path lands one tick later (the engine re-asserts the
      // interval on the next bang), so skip past that before measuring.
      await countTicks(ticks, const Duration(milliseconds: 300));
      final fast = await countTicks(ticks, const Duration(milliseconds: 1000));

      controller.setControlInt(metro, inlet: 0, value: 0);

      // ~5 ticks a second before the edit, ~25 after. Loose bounds: this is a
      // real timer thread on a shared machine, and the bug left it at ~5.
      expect(slow, inInclusiveRange(3, 7), reason: 'metro 200 ticks ~5/s');
      expect(
        fast,
        greaterThanOrEqualTo(15),
        reason: 'after the edit to 40 ms the running metro speeds up',
      );
    },
  );
}
