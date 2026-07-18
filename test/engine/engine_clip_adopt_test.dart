import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/domain_subscription_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// The engine half of issue #139: on [PhiEngine.bindProject] the engine adopts
/// the bound registry's `clip.` document into its **live** MIDI session, so
/// opening a saved project runs the edited clip rather than the boot default
/// ([defaultDemoChain]).
void main() {
  final clipAddress = EntityAddress.parse('clip.loaded');

  late FakeYseGateway gateway;
  late FakeMidiGateway midiGateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    midiGateway = FakeMidiGateway();
    engine = PhiEngine(
      gateway,
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    engine.start();
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  ProjectRegistry registryWith(ClipDocument document, {TimeDomain? domain}) {
    final registry = ProjectRegistry();
    registry.createEntity(clipAddress, payload: document.toJson());
    if (domain != null) {
      registry.createEntity(
        EntityAddress.parse('domain.${domain.name}'),
        payload: domain,
      );
    }
    return registry;
  }

  test('bindProject adopts the loaded clip into the live chain', () {
    final registry = registryWith(
      ClipDocument(
        source: MidiClip(
          name: 'loaded',
          bars: 2,
          notes: const [
            MidiNote(pitch: 61, start: 0, duration: 1, velocity: 0.42),
          ],
        ),
        chain: const [TransposeTransform(semitones: 5, label: 'loaded +5')],
      ),
    );
    addTearDown(registry.dispose);

    // The engine booted the default demo clip, which carries no pitch 61.
    expect(engine.midi.chain.source.notes.any((n) => n.pitch == 61), isFalse);

    engine.bindProject(registry);

    // The live chain now reflects the loaded document, not the boot default.
    final notes = engine.midi.chain.source.notes;
    expect(notes, hasLength(1));
    expect(notes.single.pitch, 61);
    expect(engine.midi.chain.source.bars, 2);
    expect(engine.midi.chain.transforms.single.label, 'loaded +5');
    // The shared editor now authors the adopted clip.
    expect(
      identical(engine.midi.editor.clip, engine.midi.chain.source),
      isTrue,
    );
  });

  test('adopting re-resolves a domain subscription against the project', () {
    final registry = registryWith(
      ClipDocument(
        source: MidiClip(
          name: 'loaded',
          bars: 1,
          notes: const [
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
          ],
        ),
        chain: const [
          DomainSubscriptionTransform(domainName: 'drum', label: 'domain drum'),
        ],
      ),
      domain: const TimeDomain(name: 'drum', tempo: 124),
    );
    addTearDown(registry.dispose);

    engine.bindProject(registry);

    final sub =
        engine.midi.chain.transforms.single as DomainSubscriptionTransform;
    expect(sub.domainName, 'drum');
    // Re-resolved live against the project's domain.drum, so its clock binds.
    expect(sub.boundTempo, 124);
  });

  test('adopting the loaded clip does not publish it back as an edit', () {
    final recorded = <ProjectCommand>[];
    final registry = registryWith(
      ClipDocument(
        source: MidiClip(
          name: 'loaded',
          bars: 1,
          notes: const [
            MidiNote(pitch: 61, start: 0, duration: 1, velocity: 0.5),
          ],
        ),
        chain: const [TransposeTransform(semitones: 5, label: '+5')],
      ),
    );
    addTearDown(registry.dispose);

    engine.bindProject(registry, recordCommand: recorded.add);

    // Adoption replays the loaded clip in place — it must not dirty the project.
    expect(recorded, isEmpty);

    // A genuine edit afterwards still publishes: the publisher is live and its
    // de-dupe baseline was seeded from the adopted (loaded) state.
    engine.midi.editor.addNote(
      const MidiNote(pitch: 70, start: 0, duration: 1, velocity: 0.5),
    );
    expect(recorded, hasLength(1));
  });
}
