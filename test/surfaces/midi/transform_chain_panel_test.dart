import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/custom_transform_registry.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

List<DslNote> _octaveUp(List<DslNote> notes) =>
    notes.map((n) => n.copyWith(pitch: n.pitch + 12)).toList();

void main() {
  late FakeYseGateway gateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    engine = PhiEngine(
      gateway,
      patcherGateway: FakePatcherGateway(),
      telemetryInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  MidiTransformChain oneNoteChain() => MidiTransformChain(
    source: MidiClip(
      name: 't',
      notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
      bars: 1,
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    MidiTransformChain chain,
    CustomTransformRegistry registry,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 480,
            child: MidiSurface(
              engine: engine,
              chain: chain,
              registry: registry,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('+ menu shows the empty hint until a transform is registered', (
    tester,
  ) async {
    final chain = oneNoteChain();
    final registry = CustomTransformRegistry();
    await pump(tester, chain, registry);

    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.textContaining('no custom transforms'), findsOneWidget);

    chain.dispose();
    registry.dispose();
  });

  testWidgets(
    'registered transform appears in the menu and adds to the chain',
    (tester) async {
      final chain = oneNoteChain();
      final registry = CustomTransformRegistry();
      await pump(tester, chain, registry);

      // Simulate the live-coding registration handshake.
      registry.register(
        name: 'octave up',
        kind: MidiTransformKind.pitch,
        transform: _octaveUp,
      );
      await tester.pump();

      // Open the menu — the new transform is listed.
      await tester.tap(find.text('+'));
      await tester.pump();
      expect(find.text('octave up'), findsOneWidget);
      expect(chain.transforms, isEmpty);

      // Pick it: a chip is added and the output reflects the transform.
      await tester.tap(find.text('octave up'));
      await tester.pump();

      expect(chain.transforms, hasLength(1));
      expect(find.byType(TransformChip), findsOneWidget);
      expect(chain.output.single.pitch, 72);

      chain.dispose();
      registry.dispose();
    },
  );

  testWidgets('hot-reload re-registration updates an in-chain chip live', (
    tester,
  ) async {
    final chain = oneNoteChain();
    final registry = CustomTransformRegistry();
    await pump(tester, chain, registry);

    registry.register(
      name: 'shift',
      kind: MidiTransformKind.pitch,
      transform: _octaveUp,
    );
    await tester.pump();
    await tester.tap(find.text('+'));
    await tester.pump();
    await tester.tap(find.text('shift'));
    await tester.pump();
    expect(chain.output.single.pitch, 72);

    // Re-evaluate the block with new logic: same chip, new result, no re-add.
    registry.register(
      name: 'shift',
      transform: (notes) => notes.map((n) => n.copyWith(pitch: 48)).toList(),
    );
    await tester.pump();

    expect(chain.transforms, hasLength(1));
    expect(chain.output.single.pitch, 48);

    chain.dispose();
    registry.dispose();
  });
}
