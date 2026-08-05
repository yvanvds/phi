import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/patch_bus_option.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
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

  Future<void> pumpBar(
    WidgetTester tester, {
    bool open = true,
    ValueChanged<bool>? onSnapChanged,
    ValueChanged<PatchCanvasMode>? onModeChanged,
  }) async {
    controller = PatchLibraryController(
      registry: registry,
      patches: reconciler,
      gateway: gateway,
      busOptions: () => [
        PatchBusOption(address: mix('reverb'), label: 'reverb'),
      ],
    );
    if (open) controller.open(patch('src'));
    var snap = false;
    var mode = PatchCanvasMode.edit;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PatchPlacementBar(
              controller: controller,
              snapToGrid: snap,
              onSnapChanged: onSnapChanged == null
                  ? null
                  : (on) {
                      onSnapChanged(on);
                      setState(() => snap = on);
                    },
              mode: mode,
              onModeChanged: onModeChanged == null
                  ? null
                  : (next) {
                      onModeChanged(next);
                      setState(() => mode = next);
                    },
            ),
          ),
        ),
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

  // ─── canvas grid-snap toggle (issue #368) ────────────────────────────────

  testWidgets('the snap toggle reports each flip and reflects the new state', (
    tester,
  ) async {
    registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    final reported = <bool>[];
    await pumpBar(tester, onSnapChanged: reported.add);

    Color snapColor() => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(PatchPlacementBar.snapKey),
            matching: find.byType(Icon),
          ),
        )
        .color!;
    final off = snapColor();

    await tester.tap(find.byKey(PatchPlacementBar.snapKey));
    await tester.pumpAndSettle();
    expect(reported, [true]);
    // Lit, so "is snapping on?" is answerable without dragging something.
    expect(snapColor(), isNot(off));

    await tester.tap(find.byKey(PatchPlacementBar.snapKey));
    await tester.pumpAndSettle();
    expect(reported, [true, false]);
    expect(snapColor(), off);
  });

  testWidgets('no snap toggle when nobody is listening for it', (tester) async {
    registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    await pumpBar(tester);

    expect(find.byKey(PatchPlacementBar.snapKey), findsNothing);
  });

  // ─── edit / run mode toggle (issue #378) ─────────────────────────────────

  testWidgets('the mode toggle reports each flip and names the mode it is in', (
    tester,
  ) async {
    registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    final reported = <PatchCanvasMode>[];
    await pumpBar(tester, onModeChanged: reported.add);

    Color modeColor() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(PatchPlacementBar.modeKey),
            matching: find.byType(Text),
          ),
        )
        .style!
        .color!;

    // The indicator names the mode it is *in*, not the one it would go to —
    // there is otherwise nothing on screen to say why a fader stopped moving.
    expect(find.text('EDIT'), findsOneWidget);
    final editColor = modeColor();

    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(reported, [PatchCanvasMode.run]);
    expect(find.text('RUN'), findsOneWidget);
    expect(find.text('EDIT'), findsNothing);
    expect(modeColor(), isNot(editColor));

    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(reported, [PatchCanvasMode.run, PatchCanvasMode.edit]);
    expect(find.text('EDIT'), findsOneWidget);
    expect(modeColor(), editColor);
  });

  testWidgets('no mode toggle when nobody is listening for it', (tester) async {
    registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    await pumpBar(tester);

    expect(find.byKey(PatchPlacementBar.modeKey), findsNothing);
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
