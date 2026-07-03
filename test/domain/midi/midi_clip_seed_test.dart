import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/midi/transforms/domain_subscription_transform.dart';
import 'package:phi/domain/midi/transforms/loop_transform.dart';
import 'package:phi/domain/midi/transforms/quantization_transform.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/midi/transforms/voice_routing_transform.dart';
import 'package:phi/domain/time_domains/time_domain.dart';

void main() {
  group('phraseA', () {
    test('has 10 notes spanning 4 bars', () {
      final clip = phraseA();
      expect(clip.notes, hasLength(10));
      expect(clip.bars, 4);
      expect(clip.totalBeats, 16);
    });

    test('opens with C4 at beat 0', () {
      final clip = phraseA();
      final first = clip.notes.first;
      expect(first.pitch, 60);
      expect(first.start, 0);
    });

    test('every note fits inside the clip', () {
      final clip = phraseA();
      for (final n in clip.notes) {
        expect(n.start + n.duration, lessThanOrEqualTo(clip.totalBeats));
      }
    });
  });

  group('defaultDemoChain', () {
    test('has eight transforms with the two working ones first', () {
      final chain = defaultDemoChain();
      expect(chain.transforms, hasLength(8));
      expect(chain.transforms[0], isA<ScaleConformanceTransform>());
      expect(chain.transforms[1], isA<TransposeTransform>());
    });

    test('the domain and quantize slots are both real transforms', () {
      final chain = defaultDemoChain();
      // The domain time-family chip is the real DomainSubscriptionTransform as
      // of issue #61; the quantize chip is the QuantizationTransform (#32).
      expect(chain.transforms[2], isA<DomainSubscriptionTransform>());
      expect(chain.transforms[2].label, 'domain · drum @ 124');
      expect(chain.transforms[3], isA<QuantizationTransform>());
      expect(chain.transforms[3].label, 'quantize · gravity 0.6');
    });

    test('the drum subscription tempo-locks the demo phrase to 124 BPM', () {
      final chain = defaultDemoChain();
      final domain = chain.transforms[2] as DomainSubscriptionTransform;
      expect(domain.domain, const TimeDomain(name: 'drum', tempo: 124));
      // Authored at 120, locked to 124 → beats compress by 120/124.
      expect(domain.scale, closeTo(120 / 124, 1e-9));
    });

    test('the route and agent-spawn slots are both real transforms', () {
      final chain = defaultDemoChain();
      // Voice routing is real as of issue #33; the agent-spawn chip is real as
      // of issue #37.
      expect(chain.transforms[4], isA<VoiceRoutingTransform>());
      expect(chain.transforms[4].label, 'route · osc.saw');
      expect(chain.transforms[5], isA<AgentSpawnTransform>());
      expect(chain.transforms[5].label, 'spawn · agent @ p,v');
    });

    test('the route chip sends every demo note to channel 1', () {
      final chain = defaultDemoChain();
      for (final note in chain.output) {
        expect(note.channel, 1);
      }
    });

    test('six are active, two structural ones are inactive', () {
      final chain = defaultDemoChain();
      final inactive = chain.transforms.where((t) => !t.active).toList();
      expect(inactive, hasLength(2));
      for (final t in inactive) {
        expect(t.kind, MidiTransformKind.struct);
      }
    });

    test('the loop slot is a real transform; branch stays a stub', () {
      final chain = defaultDemoChain();
      // Loop is real as of issue #34; branching waits on the DAG issue.
      expect(chain.transforms[6], isA<LoopTransform>());
      expect(chain.transforms[6].label, 'loop · 4 bars');
      expect(chain.transforms[6].active, isFalse);
      expect(chain.transforms[7], isA<StubTransform>());
      expect(chain.transforms[7].label, 'branch · state.break');
    });
  });
}
