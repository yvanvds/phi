import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/agent_spawn.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';

void main() {
  group('SpawnAxis', () {
    test('linearly remaps the source scalar into the output range', () {
      const axis = SpawnAxis(
        source: SpawnSource.pitch,
        inMin: 0,
        inMax: 127,
        outMin: 0,
        outMax: 10,
      );
      expect(
        axis.resolve(
          const MidiNote(pitch: 0, start: 0, duration: 1, velocity: 1),
        ),
        0,
      );
      expect(
        axis.resolve(
          const MidiNote(pitch: 127, start: 0, duration: 1, velocity: 1),
        ),
        10,
      );
      expect(
        axis.resolve(
          const MidiNote(pitch: 63.5, start: 0, duration: 1, velocity: 1),
        ),
        closeTo(5, 1e-9),
      );
    });

    test('clamps out-of-domain values to the nearest output edge', () {
      const axis = SpawnAxis(
        source: SpawnSource.channel,
        inMin: 0,
        inMax: 4,
        outMin: -1,
        outMax: 1,
      );
      final below = const MidiNote(
        pitch: 60,
        start: 0,
        duration: 1,
        velocity: 1,
      ).copyWith(channel: 0);
      final above = const MidiNote(
        pitch: 60,
        start: 0,
        duration: 1,
        velocity: 1,
      ).copyWith(channel: 9);
      expect(axis.resolve(below), -1);
      expect(axis.resolve(above), 1); // 9 is past inMax=4, clamps to the edge.
    });

    test('a degenerate domain maps everything to outMin', () {
      const axis = SpawnAxis(
        source: SpawnSource.velocity,
        inMin: 0.5,
        inMax: 0.5,
        outMin: 3,
        outMax: 9,
      );
      expect(
        axis.resolve(
          const MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
        ),
        3,
      );
    });

    test('.of picks sensible per-source input domains', () {
      // velocity 0..1 → the default -1..1 output.
      final vel = SpawnAxis.of(SpawnSource.velocity);
      expect(
        vel.resolve(
          const MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0),
        ),
        -1,
      );
      expect(
        vel.resolve(
          const MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        ),
        1,
      );
      // time 0..16 beats.
      final time = SpawnAxis.of(SpawnSource.time, outMin: 0, outMax: 16);
      expect(
        time.resolve(
          const MidiNote(pitch: 60, start: 8, duration: 1, velocity: 1),
        ),
        8,
      );
    });
  });

  group('AgentSpawnTransform', () {
    AgentSpawnTransform transform() => AgentSpawnTransform(
      x: SpawnAxis.of(SpawnSource.pitch, outMin: 0, outMax: 127),
      y: SpawnAxis.of(SpawnSource.velocity, outMin: 0, outMax: 1),
      z: SpawnAxis.of(SpawnSource.time, outMin: 0, outMax: 16),
      label: 'spawn',
    );

    test('is a voice-family transform that passes notes through untouched', () {
      final t = transform();
      expect(t.kind, MidiTransformKind.voice);
      const notes = [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
        MidiNote(pitch: 67, start: 2, duration: 1, velocity: 0.8),
      ];
      expect(t.apply(notes), same(notes));
    });

    test('maps a note onto a spawn: position, voice, start, lifetime', () {
      final t = transform();
      const note = MidiNote(pitch: 60, start: 4, duration: 2, velocity: 1);
      final spawn = t.spawnFor(note);
      expect(spawn.position.x, closeTo(60, 1e-9)); // pitch 60 → x 60
      expect(spawn.position.y, closeTo(1, 1e-9)); // velocity 1 → y 1
      expect(spawn.position.z, closeTo(4, 1e-9)); // start 4 → z 4
      expect(spawn.startBeat, 4);
      expect(spawn.lifetimeBeats, 2);
    });

    test(
      'voice index derives from channel, folded into the six-slot palette',
      () {
        final t = transform();
        MidiNote onChannel(int c) =>
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1, channel: c);
        expect(t.spawnFor(onChannel(0)).voiceIndex, 0);
        expect(t.spawnFor(onChannel(3)).voiceIndex, 3);
        expect(t.spawnFor(onChannel(5)).voiceIndex, 5);
        expect(t.spawnFor(onChannel(6)).voiceIndex, 0); // wraps at 6
        expect(t.spawnFor(onChannel(8)).voiceIndex, 2);
      },
    );

    test('spawnsFor maps a whole note list in order', () {
      final t = transform();
      const notes = [
        MidiNote(pitch: 0, start: 0, duration: 1, velocity: 0),
        MidiNote(pitch: 127, start: 8, duration: 1, velocity: 1),
      ];
      final spawns = t.spawnsFor(notes);
      expect(spawns, hasLength(2));
      expect(spawns[0].position.x, closeTo(0, 1e-9));
      expect(spawns[1].position.x, closeTo(127, 1e-9));
    });

    test('copyWith toggles active without disturbing the axes', () {
      final t = transform();
      final off = t.copyWith(active: false);
      expect(off.active, isFalse);
      expect(off.x, t.x);
      expect(off.y, t.y);
      expect(off.z, t.z);
      expect(off.label, t.label);
    });

    test('AgentSpawn value equality holds on identical spawns', () {
      final t = transform();
      const note = MidiNote(pitch: 62, start: 1, duration: 1, velocity: 0.5);
      final a = t.spawnFor(note);
      final b = t.spawnFor(note);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isA<AgentSpawn>());
    });
  });
}
