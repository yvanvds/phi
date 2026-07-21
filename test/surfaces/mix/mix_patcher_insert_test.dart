import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../../engine/test_doubles/fake_fx_gateway.dart';
import '../../engine/test_doubles/fake_midi_gateway.dart';
import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_synth_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// The Mix INSERTS picker offering **patchers** as insert effects (design
/// `docs/design/patcher.md` §4 role 2, issue #225): a project patch with no
/// wrapper yet is offered as `patcher · {name}`, and picking it creates + places
/// its wrapping `fx.` entity, which then behaves like any other insert.
void main() {
  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late FakePatcherGateway patchers;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    patchers = FakePatcherGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: synths,
      fxGateway: fxs,
      patcherGateway: patchers,
      telemetryInterval: const Duration(milliseconds: 50),
    );
    engine.start();
    final registry = ProjectRegistry();
    registry.createEntity(patch('swirl'), payload: PatchPayload.empty.toJson());
    registry.createEntity(patch('other'), payload: PatchPayload.empty.toJson());
    addTearDown(registry.dispose);
    engine.bindProject(registry, recordCommand: (_) {});
  });

  tearDown(() async {
    await engine.dispose();
    await midi.dispose();
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

  Future<void> openPicker(WidgetTester tester, String channel) async {
    await tester.tap(find.byKey(MixSurface.addInsertKey(channel)));
    await tester.pumpAndSettle();
  }

  testWidgets('the picker offers an unwrapped patch as a patcher insert', (
    tester,
  ) async {
    engine.addChannel(name: 'drums');
    await pumpSurface(tester);

    await openPicker(tester, 'drums');

    expect(find.text('patcher · swirl'), findsOneWidget);
  });

  testWidgets('picking a patch creates its wrapper and places it', (
    tester,
  ) async {
    final drums = engine.addChannel(name: 'drums');
    await pumpSurface(tester);
    await openPicker(tester, 'drums');

    await tester.tap(find.text('patcher · swirl').last);
    await tester.pumpAndSettle();

    // The wrapper fx entity is placed on the chain and rendered as a row.
    expect(engine.channelInserts(drums), [fx('swirl')]);
    expect(find.byKey(MixSurface.insertRowKey('drums', 'swirl')), findsOne);
    // Materialised into the live chain as a placeable patcher insert.
    expect(fxs.chains.single.walkFromHead().map((h) => h.kind.name), [
      'patcherInsert',
    ]);
  });

  testWidgets('a wrapped patch is no longer offered as a patcher option', (
    tester,
  ) async {
    engine.addChannel(name: 'drums');
    await pumpSurface(tester);
    await openPicker(tester, 'drums');
    await tester.tap(find.text('patcher · swirl').last);
    await tester.pumpAndSettle();

    // Re-open: the patch now has a wrapper, so it is not offered again (and it
    // is already on this bus, so its wrapper is not offered here either), while
    // the still-unwrapped patch stays on offer.
    await openPicker(tester, 'drums');
    expect(find.text('patcher · swirl'), findsNothing);
    expect(find.text('patcher · other'), findsOneWidget);
  });
}
