import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/commands/update_entity_payload_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// The clip-edit dirty-tracking seam (issue #135): the engine publishes the live
/// MIDI clip's edits into its `clip.` registry entity and records each as a
/// command for dirty-tracking + journaling.
void main() {
  final clipAddress = EntityAddress.parse('clip.phrase_a');

  late FakeYseGateway gateway;
  late FakeMidiGateway midiGateway;
  late PhiEngine engine;
  late ProjectRegistry registry;
  late List<ProjectCommand> recorded;

  setUp(() {
    gateway = FakeYseGateway();
    midiGateway = FakeMidiGateway();
    engine = PhiEngine(
      gateway,
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    engine.start();
    registry = ProjectRegistry();
    seedDefaultProject(registry);
    recorded = [];
    engine.bindProject(registry, recordCommand: recorded.add);
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
    registry.dispose();
  });

  ClipDocument document() => ClipDocument.fromJson(
    (registry.entityAt(clipAddress)!.payload! as Map).cast(),
  );

  test('binding alone publishes nothing (the seeded doc is left as-is)', () {
    expect(recorded, isEmpty);
    // The seed already carries source + chain.
    expect(document().chain, isNotEmpty);
  });

  test('a note edit publishes the updated clip into the registry', () {
    final before = document().source.notes.length;

    engine.midi.editor.addNote(
      const MidiNote(pitch: 62, start: 0, duration: 1, velocity: 0.5),
    );

    // The edit was recorded as an update_payload command …
    expect(recorded, hasLength(1));
    expect(recorded.single, isA<UpdateEntityPayloadCommand>());
    expect(recorded.single.entitiesTouched, {clipAddress});
    // … and the registry entity now carries the added note.
    final after = document().source.notes;
    expect(after, hasLength(before + 1));
    expect(after.any((n) => n.pitch == 62), isTrue);
  });

  test('a length edit publishes the updated meter (issue #190)', () {
    engine.midi.editor.setLength(bars: 8, beatsPerBar: 3);

    expect(recorded, hasLength(1));
    expect(recorded.single, isA<UpdateEntityPayloadCommand>());
    expect(document().source.bars, 8);
    expect(document().source.beatsPerBar, 3);
  });

  test('toggling the loop flag publishes it into the payload (issue #190)', () {
    // The seed defaults loop on; the payload round-trips it.
    expect(document().loop, isTrue);

    engine.midi.loop = false;

    expect(recorded, hasLength(1));
    expect(recorded.single, isA<UpdateEntityPayloadCommand>());
    expect(document().loop, isFalse);

    // Toggling back re-publishes, and the earlier default is no longer forced.
    engine.midi.loop = true;
    expect(document().loop, isTrue);
    expect(recorded, hasLength(2));
  });

  test('a chip toggle publishes the updated chain', () {
    final wasActive = engine.midi.chain.transforms.first.active;

    engine.midi.chain.setActiveAt(0, !wasActive);

    expect(recorded, hasLength(1));
    expect(recorded.single, isA<UpdateEntityPayloadCommand>());
    expect(document().chain.first.active, !wasActive);
  });

  test('a selection-only change publishes nothing (dedupe)', () {
    engine.midi.editor.selectOnly(0);
    expect(recorded, isEmpty);
  });

  test('rebinding a fresh project stops publishing into the old one', () {
    final other = ProjectRegistry();
    addTearDown(other.dispose);
    seedDefaultProject(other);
    final otherRecorded = <ProjectCommand>[];
    engine.bindProject(other, recordCommand: otherRecorded.add);

    engine.midi.editor.addNote(
      const MidiNote(pitch: 64, start: 0, duration: 1, velocity: 0.5),
    );

    // The old registry no longer receives edits; the new one does.
    expect(recorded, isEmpty);
    expect(otherRecorded, hasLength(1));
  });
}
