import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/domain/voice/voice_kind.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';
import 'package:phi/engine/state/rack_definitions_controller.dart';
import 'package:phi/engine/state/voice_audition_controller.dart';
import 'package:phi/surfaces/racks/voices_pane.dart';

import '../../engine/test_doubles/fake_midi_gateway.dart';
import '../../engine/test_doubles/fake_synth_gateway.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
);

void main() {
  late ProjectRegistry registry;
  late RackDefinitionsController controller;
  late FakeMidiGateway gateway;
  late EngineMidiController midi;
  late FakeMaterialisedSynth synthBass;
  late FakeMaterialisedSynth synthLead;
  late VoiceAuditionController audition;

  final bass = _addr('voice.bass');
  final lead = _addr('voice.lead');

  void seed() {
    registry.createEntity(
      _addr('synth.a'),
      payload: const SineSynth().toJson(),
    );
    registry.createEntity(
      _addr('synth.b'),
      payload: const SineSynth().toJson(),
    );
    registry.createEntity(
      bass,
      payload: VoiceDefinition.internal(
        synth: _addr('synth.a'),
        output: _addr('mix.master'),
        color: 'voice1',
      ).toJson(),
    );
    registry.createEntity(
      lead,
      payload: VoiceDefinition.internal(
        // Also synth.a, so the synth-picker test can find the 'b' option
        // unambiguously (no closed control shows 'b').
        synth: _addr('synth.a'),
        output: _addr('mix.master'),
        color: 'voice2',
      ).toJson(),
    );
  }

  setUp(() {
    registry = ProjectRegistry();
    controller = RackDefinitionsController(registry: registry);
    gateway = FakeMidiGateway();
    midi = EngineMidiController(chain: _seedChain(), gateway: gateway);
    synthBass = FakeMaterialisedSynth(const SineSynth(), channel: 1);
    synthLead = FakeMaterialisedSynth(const SineSynth(), channel: 2);
    midi.bindVoices(VoiceChannelResolver.seededDefault(), {
      'voice.bass': synthBass,
      'voice.lead': synthLead,
    });
    audition = VoiceAuditionController(midi: midi);
    addTearDown(() async {
      audition.dispose();
      midi.dispose();
      await gateway.dispose();
      controller.dispose();
      registry.dispose();
    });
  });

  Future<void> pump(WidgetTester tester, {bool withAudition = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 700,
            child: VoicesPane(
              controller: controller,
              audition: withAudition ? audition : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders an editable card per voice with kind + pickers', (
    tester,
  ) async {
    seed();
    await pump(tester);

    expect(find.byKey(VoicesPane.rowKey(bass)), findsOneWidget);
    expect(find.byKey(VoicesPane.rowKey(lead)), findsOneWidget);
    // Kind segments, synth picker, bus picker, and colour swatches render.
    expect(
      find.byKey(VoicesPane.kindKey(bass, VoiceKind.internal)),
      findsOneWidget,
    );
    expect(
      find.byKey(VoicesPane.kindKey(bass, VoiceKind.external)),
      findsOneWidget,
    );
    expect(find.byKey(VoicesPane.synthKey(bass)), findsOneWidget);
    expect(find.byKey(VoicesPane.busKey(bass)), findsOneWidget);
    expect(find.byKey(VoicesPane.colorKey(bass, 'voice3')), findsOneWidget);
  });

  testWidgets('switching a voice to external swaps to a channel picker', (
    tester,
  ) async {
    seed();
    await pump(tester);

    await tester.tap(find.byKey(VoicesPane.kindKey(bass, VoiceKind.external)));
    await tester.pumpAndSettle();

    final voice = controller.voiceAt(bass)!;
    expect(voice.kind, VoiceKind.external);
    expect(voice.channel, 1);
    // The row now shows the channel picker instead of the synth picker.
    expect(find.byKey(VoicesPane.channelKey(bass)), findsOneWidget);
    expect(find.byKey(VoicesPane.synthKey(bass)), findsNothing);
  });

  testWidgets('picking a synth re-binds the voice', (tester) async {
    seed();
    await pump(tester);

    await tester.tap(find.byKey(VoicesPane.synthKey(bass)));
    await tester.pumpAndSettle();
    // The picker lists both synths; choose synth.b (the only 'b' on screen).
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();

    expect(controller.voiceAt(bass)!.synth, _addr('synth.b'));
  });

  testWidgets('picking a colour swatch recolours the voice', (tester) async {
    seed();
    await pump(tester);

    await tester.tap(find.byKey(VoicesPane.colorKey(bass, 'voice4')));
    await tester.pumpAndSettle();

    expect(controller.voiceAt(bass)!.color, 'voice4');
  });

  testWidgets('arm is single: arming one voice disarms the other', (
    tester,
  ) async {
    seed();
    await pump(tester);

    await tester.tap(find.byKey(VoicesPane.armKey(bass)));
    await tester.pumpAndSettle();
    expect(audition.armed, bass);

    await tester.tap(find.byKey(VoicesPane.armKey(lead)));
    await tester.pumpAndSettle();
    expect(audition.armed, lead);
    expect(audition.isArmed(bass), isFalse);

    // Tapping the armed voice's toggle disarms it.
    await tester.tap(find.byKey(VoicesPane.armKey(lead)));
    await tester.pumpAndSettle();
    expect(audition.armed, isNull);
  });

  testWidgets('the test strip auditions the armed voice from the mouse', (
    tester,
  ) async {
    seed();
    await pump(tester);

    // Disabled until a voice is armed.
    expect(find.text('arm a voice to audition'), findsOneWidget);

    await tester.tap(find.byKey(VoicesPane.armKey(bass)));
    await tester.pumpAndSettle();

    // Press a key: the armed voice sounds; release stops it.
    final key = find.byKey(VoicesPane.testKeyKey(60));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump();
    expect(synthBass.heldNotes, contains(60));
    expect(synthLead.noteLog, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(synthBass.heldNotes, isEmpty);
  });

  testWidgets('the header + adds a voice', (tester) async {
    seed();
    await pump(tester);

    await tester.tap(find.byKey(VoicesPane.addKey));
    await tester.pumpAndSettle();

    expect(registry.contains(_addr('voice.voice')), isTrue);
  });

  testWidgets('the row menu deletes a voice after confirm', (tester) async {
    seed();
    await pump(tester);

    await tester.tap(find.byKey(VoicesPane.menuKey(lead)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'delete'));
    await tester.pumpAndSettle();

    expect(registry.contains(lead), isFalse);
  });

  testWidgets('without an audition seam, arming + strip are disabled', (
    tester,
  ) async {
    seed();
    await pump(tester, withAudition: false);

    // Rows still render and edit; the strip shows its disabled hint.
    expect(find.byKey(VoicesPane.rowKey(bass)), findsOneWidget);
    expect(find.text('arm a voice to audition'), findsOneWidget);
    // Tapping arm does nothing (no seam).
    await tester.tap(find.byKey(VoicesPane.armKey(bass)));
    await tester.pumpAndSettle();
    expect(find.byKey(VoicesPane.testKeyKey(60)), findsNothing);
  });
}
