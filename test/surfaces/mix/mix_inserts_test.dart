import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../../engine/test_doubles/fake_fx_gateway.dart';
import '../../engine/test_doubles/fake_synth_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// The Mix **INSERTS** area (issue #212, racks design §5): each strip's ordered
/// `fx.` chain — place from a picker over unplaced fx, reorder by drag, remove,
/// and the move-with-impact flow when an fx already sits on another bus. Driven
/// as widgets against the fakes; the fx materialisation itself is `engine_racks`.
void main() {
  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);

  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    engine = PhiEngine(
      yse,
      synthGateway: synths,
      fxGateway: fxs,
      telemetryInterval: const Duration(milliseconds: 50),
    );
    engine.start();
    final registry = ProjectRegistry();
    registry.createEntity(
      fx('big_delay'),
      payload: const FxDefinition(kind: FxKind.lowpassDelay).toJson(),
    );
    registry.createEntity(
      fx('crush'),
      payload: const FxDefinition(kind: FxKind.compressor).toJson(),
    );
    addTearDown(registry.dispose);
    engine.bindProject(registry, recordCommand: (_) {});
  });

  tearDown(() async {
    await engine.dispose();
    await yse.dispose();
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MixSurface(engine: engine)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the add-insert picker on [channel] and taps the option labelled
  /// [optionLabel] in the opened menu.
  Future<void> placeInsert(
    WidgetTester tester,
    String channel,
    String optionLabel,
  ) async {
    await tester.tap(find.byKey(MixSurface.addInsertKey(channel)));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addInsertKey(channel)),
            matching: find.text(optionLabel),
          )
          .last,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the INSERTS area appears once a channel + fx exist', (
    tester,
  ) async {
    engine.addChannel(name: 'drums');
    await pumpSurface(tester);

    expect(find.text('INSERTS'), findsOneWidget);
    expect(find.byKey(MixSurface.addInsertKey('drums')), findsOneWidget);
  });

  testWidgets('picking an unplaced fx places it on the chain', (tester) async {
    final drums = engine.addChannel(name: 'drums');
    await pumpSurface(tester);

    await placeInsert(tester, 'drums', 'big_delay');

    expect(engine.channelInserts(drums), [fx('big_delay')]);
    // The row renders the fx name + its kind.
    expect(find.byKey(MixSurface.insertRowKey('drums', 'big_delay')), findsOne);
    expect(find.text('lowpassDelay'), findsOneWidget);
  });

  testWidgets('the remove control detaches an insert', (tester) async {
    final drums = engine.addChannel(name: 'drums');
    await pumpSurface(tester);
    await placeInsert(tester, 'drums', 'big_delay');
    expect(engine.channelInserts(drums), [fx('big_delay')]);

    await tester.tap(find.byKey(MixSurface.insertRemoveKey('drums', 0)));
    await tester.pumpAndSettle();

    expect(engine.channelInserts(drums), isEmpty);
  });

  testWidgets('dragging a grip reorders the chain', (tester) async {
    final drums = engine.addChannel(name: 'drums');
    await pumpSurface(tester);
    await placeInsert(tester, 'drums', 'big_delay');
    await placeInsert(tester, 'drums', 'crush');
    expect(engine.channelInserts(drums), [fx('big_delay'), fx('crush')]);

    // Drop crush's grip onto the big_delay row → crush leads.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(MixSurface.insertDragKey('drums', 'crush'))),
    );
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(
        find.byKey(MixSurface.insertRowKey('drums', 'big_delay')),
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(engine.channelInserts(drums), [fx('crush'), fx('big_delay')]);
  });

  testWidgets('placing an fx from another bus confirms, then moves it', (
    tester,
  ) async {
    final drums = engine.addChannel(name: 'drums');
    final bass = engine.addChannel(name: 'bass');
    engine.addChannelInsert(drums, fx('big_delay'));
    await pumpSurface(tester);

    // On bass, the picker offers it annotated with its current bus.
    await tester.tap(find.byKey(MixSurface.addInsertKey('bass')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addInsertKey('bass')),
            matching: find.text('big_delay · on drums'),
          )
          .last,
    );
    await tester.pumpAndSettle();

    // A confirm dialog names the losing bus; confirming performs the move.
    expect(find.text('move insert'), findsOneWidget);
    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();

    expect(engine.channelInserts(drums), isEmpty);
    expect(engine.channelInserts(bass), [fx('big_delay')]);
  });

  testWidgets('cancelling the move dialog leaves the placement untouched', (
    tester,
  ) async {
    final drums = engine.addChannel(name: 'drums');
    final bass = engine.addChannel(name: 'bass');
    engine.addChannelInsert(drums, fx('big_delay'));
    await pumpSurface(tester);

    await tester.tap(find.byKey(MixSurface.addInsertKey('bass')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(MixSurface.addInsertKey('bass')),
            matching: find.text('big_delay · on drums'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(engine.channelInserts(drums), [fx('big_delay')]);
    expect(engine.channelInserts(bass), isEmpty);
  });
}
