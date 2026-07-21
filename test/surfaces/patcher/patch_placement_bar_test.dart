import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/patch_bus_option.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget coverage for the patcher **source-placement bar** (issue #224): pick a
/// mix bus over a [PhiSelect] and start / stop the placed source — the placement
/// reaching the payload and the start / stop reaching the fake gateway.
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakePatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late PatchLibraryController controller;

  final buses = <EntityAddress, int?>{mix('reverb'): 7};

  setUp(() {
    gateway = FakePatcherGateway();
    registry = ProjectRegistry();
    reconciler = PatchReconciler(
      gateway: gateway,
      resolveBus: (a) => buses.containsKey(a) ? (channelId: buses[a]) : null,
      onNotice: (_) {},
    );
  });

  tearDown(() {
    controller.dispose();
    registry.dispose();
  });

  Future<void> pumpBar(WidgetTester tester, {bool open = true}) async {
    controller = PatchLibraryController(
      registry: registry,
      patches: reconciler,
      gateway: gateway,
      busOptions: () => [
        PatchBusOption(address: mix('reverb'), label: 'reverb'),
      ],
    );
    if (open) controller.open(patch('src'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PatchPlacementBar(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a hint when no patch is open', (tester) async {
    await pumpBar(tester, open: false);

    expect(find.text('no patch open'.toUpperCase()), findsOneWidget);
    expect(find.byKey(PatchPlacementBar.startStopKey), findsNothing);
  });

  testWidgets('picking a bus places the source (persisted in the payload)', (
    tester,
  ) async {
    registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    await pumpBar(tester);

    await tester.tap(find.byKey(PatchPlacementBar.placeSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('reverb').last);
    await tester.pumpAndSettle();

    expect(controller.placementOf(patch('src')), mix('reverb'));
    final payload = PatchPayload.fromJson(
      (registry.entityAt(patch('src'))!.payload! as Map).cast(),
    );
    expect(payload.placement, mix('reverb'));
  });

  testWidgets('start mounts the placed source, stop unmounts it', (
    tester,
  ) async {
    registry.createEntity(
      patch('src'),
      payload: PatchPayload(placement: mix('reverb')).toJson(),
    );
    await pumpBar(tester);
    final id = reconciler.instanceIdOf(patch('src'));

    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    expect(controller.isRunning(patch('src')), isTrue);
    expect(gateway.calls, contains('mountAsSource:$id:7:1.000'));

    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();
    expect(controller.isRunning(patch('src')), isFalse);
    expect(gateway.calls, contains('unmountSource:$id'));
  });

  testWidgets('an unplaced source cannot be started', (tester) async {
    registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    await pumpBar(tester);

    await tester.tap(find.byKey(PatchPlacementBar.startStopKey));
    await tester.pumpAndSettle();

    expect(controller.isRunning(patch('src')), isFalse);
    expect(gateway.mounted, isFalse);
  });
}
