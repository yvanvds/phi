import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  late FakeYseGateway gateway;
  late FakePatcherGateway patcherGateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    patcherGateway = FakePatcherGateway();
    engine = PhiEngine(
      gateway,
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  Future<void> pumpSurface(
    WidgetTester tester, {
    MidiTransformChain? chain,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 480,
            child: MidiSurface(engine: engine, chain: chain),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the seeded clip and eight transform chips', (
    tester,
  ) async {
    await pumpSurface(tester);

    expect(find.textContaining('phrase A'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('interpreted, not played'), findsOneWidget);
    expect(find.text('D DORIAN'), findsOneWidget);
    expect(find.text('DOMAIN · DRUM'), findsOneWidget);
    expect(find.byType(TransformChip), findsNWidgets(8));
  });

  testWidgets('tapping a chip flips active on the underlying transform', (
    tester,
  ) async {
    final chain = MidiTransformChain(
      source: const MidiClip(
        name: 't',
        notes: [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
        bars: 1,
      ),
      transforms: const [
        TransposeTransform(semitones: 5, label: '+5'),
        StubTransform(
          kind: MidiTransformKind.struct,
          label: 'loop · 4 bars',
          active: false,
        ),
      ],
    );

    await pumpSurface(tester, chain: chain);

    final chips = find.byType(TransformChip);
    expect(chips, findsNWidgets(2));
    expect(chain.transforms[0].active, isTrue);
    expect(chain.output.single.pitch, 65);

    await tester.tap(chips.first);
    await tester.pump();

    expect(chain.transforms[0].active, isFalse);
    expect(chain.output.single.pitch, 60);

    await tester.tap(chips.last);
    await tester.pump();
    expect(chain.transforms[1].active, isTrue);

    chain.dispose();
  });

  testWidgets('default demo chain renders the mockup chip labels', (
    tester,
  ) async {
    final chain = defaultDemoChain();
    await pumpSurface(tester, chain: chain);

    expect(find.byType(TransformChip), findsNWidgets(8));
    // Chip labels render mixed-case — only headers/tags uppercase.
    expect(find.text('scale · dorian D'), findsOneWidget);
    expect(find.text('transpose · +3 st'), findsOneWidget);
    expect(find.text('loop · 4 bars'), findsOneWidget);

    chain.dispose();
  });
}
