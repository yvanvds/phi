import 'package:vector_math/vector_math_64.dart';

import '../time_domains/time_domain.dart';
import '../time_domains/time_domain_registry.dart';
import 'midi_clip.dart';
import 'midi_note.dart';
import 'midi_transform.dart';
import 'midi_transform_chain.dart';
import 'midi_transform_kind.dart';
import 'music_scale.dart';
import 'spawn_axis.dart';
import 'spawn_source.dart';
import 'transforms/agent_spawn_transform.dart';
import 'transforms/domain_subscription_transform.dart';
import 'transforms/loop_transform.dart';
import 'transforms/quantization_transform.dart';
import 'transforms/scale_conformance_transform.dart';
import 'transforms/stub_transform.dart';
import 'transforms/transpose_transform.dart';
import 'transforms/voice_routing_rule.dart';
import 'transforms/voice_routing_transform.dart';

/// The registry address leaf of the seeded demo clip (`clip.phrase_a`). With the
/// free-form display name dropped (issue #184) the clip is named by this leaf
/// everywhere — the library, the editor header, live code — so the seed and the
/// MIDI surface header share this one source of truth.
const String phraseASlug = 'phrase_a';

/// The ten-note "phrase A" used as the on-load demo clip. Matches the
/// surface-midi.jsx mockup note-for-note — pitch classes include scale
/// degrees both inside and outside D-dorian so scale-conformance has
/// something visible to do when the user toggles it.
MidiClip phraseA() => MidiClip(
  bars: 4,
  notes: const [
    MidiNote(pitch: 60, start: 0.00, duration: 0.25, velocity: 0.7),
    MidiNote(pitch: 63, start: 0.25, duration: 0.25, velocity: 0.6),
    MidiNote(pitch: 67, start: 0.50, duration: 0.50, velocity: 0.8),
    MidiNote(pitch: 70, start: 1.00, duration: 0.25, velocity: 0.5),
    MidiNote(pitch: 67, start: 1.25, duration: 0.25, velocity: 0.6),
    MidiNote(pitch: 65, start: 1.50, duration: 0.50, velocity: 0.7),
    MidiNote(pitch: 63, start: 2.00, duration: 0.25, velocity: 0.5),
    MidiNote(pitch: 67, start: 2.25, duration: 0.75, velocity: 0.9),
    MidiNote(pitch: 70, start: 3.00, duration: 0.50, velocity: 0.7),
    MidiNote(pitch: 72, start: 3.50, duration: 0.50, velocity: 0.8),
  ],
);

/// The demo time-domains the seed chain resolves against. Just the `drum`
/// domain @ 124 BPM the mockup's `domain · drum @ 124` chip subscribes to;
/// more domains land with the time-domains surface. Subscribing binds the
/// clip's transport clock to this domain's tempo (issue #102) — the beats stay
/// as authored, the clock runs at 124.
final TimeDomainRegistry demoTimeDomains = TimeDomainRegistry(const [
  TimeDomain(name: 'drum', tempo: 124),
]);

/// The eight-chip default sidebar from the design mockup — six working
/// transforms (scale-conform, transpose, domain-subscribe, quantize, route,
/// loop) and two stubs covering slots whose implementations are still open
/// issues. The last two structural chips ship `active: false` to mirror the
/// mockup state.
MidiTransformChain defaultDemoChain() => MidiTransformChain(
  source: phraseA(),
  transforms: <MidiTransform>[
    ScaleConformanceTransform.diatonic(
      scale: MusicScale.dorian,
      tonic: 62,
      label: 'scale · dorian D',
    ),
    const TransposeTransform(semitones: 3, label: 'transpose · +3 st'),
    DomainSubscriptionTransform.resolve(
      registry: demoTimeDomains,
      domainName: 'drum',
      label: 'domain · drum @ 124',
    ),
    const QuantizationTransform(gravity: 0.6, label: 'quantize · gravity 0.6'),
    const VoiceRoutingTransform(
      rules: [PitchRangeRule(minPitch: 0, maxPitch: 127, channel: 1)],
      label: 'route · osc.saw',
    ),
    AgentSpawnTransform(
      // Pitch drives X, velocity lifts Y, and the note's start beat pushes it
      // back along Z — so the phrase scatters across the Scene as it plays.
      x: SpawnAxis.of(SpawnSource.pitch),
      y: SpawnAxis.of(SpawnSource.velocity),
      z: SpawnAxis.of(SpawnSource.time),
      // Gentle upward drift so spawned agents rise while they live rather than
      // hanging static (issue #79). The scene camera's up axis is +Z
      // (`Vector3(0, 0, 1)`), so drifting +Z reads as rising on screen; +Y
      // would drift toward the lower-right instead (issue #89). Scene units /
      // second.
      velocity: Vector3(0, 0, 0.2),
      label: 'spawn · agent @ p,v',
    ),
    const LoopTransform(
      loopLengthBeats: 16,
      repeatCount: 2,
      label: 'loop · 4 bars',
      active: false,
    ),
    const StubTransform(
      kind: MidiTransformKind.struct,
      label: 'branch · state.break',
      active: false,
    ),
  ],
);
