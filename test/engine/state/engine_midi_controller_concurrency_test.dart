import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/midi/transforms/domain_subscription_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_scene_renderer.dart';

/// The boot session's seed chain — one note, one transpose chip.
MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
  transforms: const [TransposeTransform(semitones: 1, label: 'seed +1')],
);

EntityAddress _clip(String name) =>
    EntityAddress(kind: 'clip', segments: [name]);

EntityAddress _clipPath(List<String> segments) =>
    EntityAddress(kind: 'clip', segments: segments);

/// A chain-only document for [pitch] (loop on unless [loop] says otherwise).
ClipDocument _chainDoc(double pitch, {bool loop = true}) => ClipDocument(
  source: MidiClip(
    bars: 2,
    notes: [MidiNote(pitch: pitch, start: 0, duration: 1, velocity: 1)],
  ),
  loop: loop,
);

/// A document whose chain subscribes to a domain at [tempo] BPM, so the played
/// clock runs at that tempo — the seam concurrent per-clock playback rides.
ClipDocument _subscribedDoc(double tempo) => ClipDocument(
  source: MidiClip(
    bars: 2,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
  chain: [
    DomainSubscriptionTransform(
      domainName: 'dom$tempo',
      label: 'sub',
      domain: TimeDomain(name: 'dom$tempo', tempo: tempo),
    ),
  ],
);

AgentSpawnTransform _spawn() => AgentSpawnTransform(
  x: SpawnAxis.of(SpawnSource.pitch, outMin: 0, outMax: 127),
  y: SpawnAxis.of(SpawnSource.velocity, outMin: 0, outMax: 1),
  z: SpawnAxis.of(SpawnSource.time, outMin: 0, outMax: 4),
  label: 'spawn',
);

/// A document whose single note is identical across clips (channel 0, pitch 60)
/// and whose chain spawns a scene agent — so two of them collide on the voice
/// key `0 * 128 + 60` unless the sessions are namespaced apart.
ClipDocument _spawnDoc() => ClipDocument(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
  chain: [_spawn()],
);

void main() {
  group('EngineMidiController — concurrent playback (#187)', () {
    test('two clips play at once, each on its own clock and tempo', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: gateway,
        );

        final fast = controller.openSession(_clip('fast'), _subscribedDoc(150));
        final slow = controller.openSession(_clip('slow'), _subscribedDoc(90));

        expect(controller.playSession(_clip('fast')), isTrue);
        expect(controller.playSession(_clip('slow')), isTrue);
        async.elapse(const Duration(milliseconds: 50));

        // Both run concurrently…
        expect(fast.isPlaying, isTrue);
        expect(slow.isPlaying, isTrue);

        // …on two distinct domain clocks (one transport each).
        expect(gateway.transports, hasLength(2));
        final byClock = {for (final t in gateway.transports) t.clockName: t};
        expect(byClock.keys, hasLength(2));

        // Each clock runs at its own tempo, independent of the other — the
        // polytemporal shape the engine already supports.
        expect(byClock['phi.midi.clip.fast']!.tempo, closeTo(150, 1e-9));
        expect(byClock['phi.midi.clip.slow']!.tempo, closeTo(90, 1e-9));

        controller.dispose();
      });
    });

    test(
      'playSession is independent — pausing one leaves the other playing',
      () {
        fakeAsync((async) {
          final controller = EngineMidiController(
            chain: _seedChain(),
            gateway: FakeMidiGateway(),
          );
          final a = controller.openSession(_clip('a'), _chainDoc(60));
          final b = controller.openSession(_clip('b'), _chainDoc(62));
          controller.playSession(_clip('a'));
          controller.playSession(_clip('b'));
          async.elapse(const Duration(milliseconds: 20));

          expect(controller.pauseSession(_clip('a')), isTrue);
          expect(a.isPaused, isTrue);
          expect(a.isPlaying, isFalse);
          expect(b.isPlaying, isTrue); // untouched

          // playSession resumes a paused clip rather than restarting it.
          expect(controller.playSession(_clip('a')), isTrue);
          expect(a.isPlaying, isTrue);
          expect(a.isPaused, isFalse);

          controller.dispose();
        });
      },
    );

    test('stopGroup stops every clip beneath the group, not its siblings', () {
      fakeAsync((async) {
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: FakeMidiGateway(),
        );

        final kick = _clipPath(['drums', 'kick']);
        final snare = _clipPath(['drums', 'snare']);
        final bass = _clip('bass');
        controller.openSession(kick, _chainDoc(36));
        controller.openSession(snare, _chainDoc(38));
        controller.openSession(bass, _chainDoc(28));
        controller.playSession(kick);
        controller.playSession(snare);
        controller.playSession(bass);
        async.elapse(const Duration(milliseconds: 20));
        expect(controller.sessionFor(kick)!.isPlaying, isTrue);

        controller.stopGroup(_clip('drums'));

        expect(controller.sessionFor(kick)!.isPlaying, isFalse);
        expect(controller.sessionFor(snare)!.isPlaying, isFalse);
        // The bass sits outside `clip.drums` — it keeps playing.
        expect(controller.sessionFor(bass)!.isPlaying, isTrue);

        controller.dispose();
      });
    });

    test('playGroup starts every clip beneath the group', () {
      fakeAsync((async) {
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: FakeMidiGateway(),
        );
        final kick = _clipPath(['drums', 'kick']);
        final snare = _clipPath(['drums', 'snare']);
        controller.openSession(kick, _chainDoc(36));
        controller.openSession(snare, _chainDoc(38));

        controller.playGroup(_clip('drums'));
        async.elapse(const Duration(milliseconds: 20));

        expect(controller.sessionFor(kick)!.isPlaying, isTrue);
        expect(controller.sessionFor(snare)!.isPlaying, isTrue);

        controller.dispose();
      });
    });

    test('stopAll stops every session — playing and paused alike', () {
      fakeAsync((async) {
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: FakeMidiGateway(),
        );
        final a = controller.openSession(_clip('a'), _chainDoc(60));
        final b = controller.openSession(_clip('b'), _chainDoc(62));
        controller.play(); // the boot (edited) session
        controller.playSession(_clip('a'));
        controller.playSession(_clip('b'));
        async.elapse(const Duration(milliseconds: 20));
        controller.pauseSession(_clip('b'));

        controller.stopAll();

        expect(controller.editedSession.isPlaying, isFalse);
        expect(a.isPlaying, isFalse);
        expect(b.isPlaying, isFalse);
        expect(b.isPaused, isFalse);

        controller.dispose();
      });
    });

    test('a clip opened with loop off plays one-shot', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: gateway,
        );
        controller.openSession(_clip('once'), _chainDoc(60, loop: false));
        controller.playSession(_clip('once'));
        async.elapse(const Duration(milliseconds: 20));

        expect(gateway.transport!.loopBeats, lessThanOrEqualTo(0));

        controller.dispose();
      });
    });

    test('concurrent clips spawn side by side; stopping one clears only its '
        'own agents', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        // Two clips whose single note is identical (channel 0, pitch 60). Their
        // voice keys would collide on the one shared field without per-session
        // namespacing — one agent would overwrite the other.
        final a = controller.openSession(_clip('a'), _spawnDoc());
        final b = controller.openSession(_clip('b'), _spawnDoc());
        controller.playSession(_clip('a'));
        controller.playSession(_clip('b'));
        // Cross both note-ons (beat 0), still before their note-offs (beat 1).
        async.elapse(const Duration(milliseconds: 50));

        // Both agents live — the keys did not collide.
        expect(renderer.lastAgents, hasLength(2));

        // Stopping clip A clears exactly A's agent; B's survives.
        controller.stopSession(_clip('a'));
        expect(renderer.lastAgents, hasLength(1));
        expect(a.isPlaying, isFalse);
        expect(b.isPlaying, isTrue);

        controller.dispose();
      });
    });
  });
}
