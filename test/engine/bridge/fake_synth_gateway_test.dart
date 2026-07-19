import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/sampler_synth.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/synth_kind.dart';
import 'package:phi/domain/synth/va_filter.dart';
import 'package:phi/domain/synth/va_synth.dart';

import '../test_doubles/fake_midi_transport.dart';
import '../test_doubles/fake_synth_gateway.dart';

void main() {
  late FakeSynthGateway gateway;

  setUp(() => gateway = FakeSynthGateway());

  group('materialisation — every kind', () {
    test('sine materialises on its allocated channel', () {
      final synth = gateway.materialiseSynth(const SineSynth(), channel: 3);
      expect(synth.kind, SynthKind.sine);
      expect(synth.channel, 3);
      expect(gateway.last!.materialiseCount, 1);
      expect(gateway.last!.calls, ['materialise:sine']);
    });

    test('va materialises', () {
      final synth = gateway.materialiseSynth(const VaSynth(), channel: 1);
      expect(synth.kind, SynthKind.va);
      expect(synth.definition, isA<VaSynth>());
    });

    test('fm materialises', () {
      final synth = gateway.materialiseSynth(
        const FmSynth(bankAsset: 'assets/bells.syx'),
        channel: 5,
      );
      expect(synth.kind, SynthKind.fm);
      expect(synth.channel, 5);
    });

    test('sampler materialises', () {
      final synth = gateway.materialiseSynth(
        const SamplerSynth(sfzAsset: 'assets/piano.sfz'),
        channel: 2,
      );
      expect(synth.kind, SynthKind.sampler);
    });

    test('each call mints a distinct handle', () {
      gateway.materialiseSynth(const SineSynth(), channel: 1);
      gateway.materialiseSynth(const VaSynth(), channel: 2);
      expect(gateway.synths, hasLength(2));
      expect(gateway.synths[0], isNot(same(gateway.synths[1])));
    });
  });

  group('definition re-application', () {
    test('a live VA param edit applies in place, no rebuild', () {
      final synth = gateway.materialiseSynth(
        const VaSynth(filter: VaFilter(cutoff: 20000)),
        channel: 1,
      );
      synth.applyDefinition(const VaSynth(filter: VaFilter(cutoff: 500)));

      expect(gateway.last!.materialiseCount, 1);
      expect(gateway.last!.liveApplyCount, 1);
      expect((synth.definition as VaSynth).filter.cutoff, 500);
      expect(gateway.last!.calls, ['materialise:va', 'apply:va']);
    });

    test('a voice-count edit rebuilds the pool', () {
      final synth = gateway.materialiseSynth(
        const VaSynth(voiceCount: 8),
        channel: 1,
      );
      synth.applyDefinition(const VaSynth(voiceCount: 16));

      expect(gateway.last!.materialiseCount, 2);
      expect(gateway.last!.liveApplyCount, 0);
    });

    test('an FM bank swap rebuilds; a patch tweak is live', () {
      final synth = gateway.materialiseSynth(
        const FmSynth(bankAsset: 'assets/bells.syx'),
        channel: 1,
      );
      synth.applyDefinition(
        const FmSynth(bankAsset: 'assets/bells.syx', patchIndex: 4),
      );
      expect(gateway.last!.liveApplyCount, 1);
      expect(gateway.last!.materialiseCount, 1);

      synth.applyDefinition(const FmSynth(bankAsset: 'assets/brass.syx'));
      expect(gateway.last!.materialiseCount, 2);
    });

    test('a rebuild re-binds the sound to the same bus', () {
      final synth = gateway.materialiseSynth(
        const VaSynth(voiceCount: 8),
        channel: 1,
      );
      synth.bindToBus(7);
      final bindsBefore = gateway.last!.bindCount;

      synth.applyDefinition(const VaSynth(voiceCount: 4)); // rebuild

      expect(synth.boundBus, 7, reason: 'the bus survives a rebuild');
      expect(
        gateway.last!.bindCount,
        bindsBefore + 1,
        reason: 'the rebuild re-binds the sound',
      );
      expect(gateway.last!.calls, contains('bind:7'));
    });
  });

  group('bus binding', () {
    test('binds to a mix bus and re-points on rebind', () {
      final synth = gateway.materialiseSynth(const SineSynth(), channel: 1);
      expect(synth.boundBus, isNull);

      synth.bindToBus(4);
      expect(synth.boundBus, 4);

      synth.bindToBus(9);
      expect(synth.boundBus, 9, reason: 're-pointing behind a stable identity');
      expect(gateway.last!.bindCount, 2);
    });

    test('a null bus binds to the master bus', () {
      final synth = gateway.materialiseSynth(const SineSynth(), channel: 1);
      synth.bindToBus(null);
      expect(synth.boundBus, isNull);
      expect(gateway.last!.calls, contains('bind:null'));
    });
  });

  group('disposal', () {
    test('disposes the sound before the synth (leak-safe order)', () {
      final synth = gateway.materialiseSynth(const SineSynth(), channel: 1);
      synth.bindToBus(1);
      synth.dispose();

      expect(gateway.last!.isDisposed, isTrue);
      final calls = gateway.last!.calls;
      expect(
        calls.indexOf('dispose:sound'),
        lessThan(calls.indexOf('dispose:synth')),
      );
    });

    test('an unbound synth disposes only the synth', () {
      final synth = gateway.materialiseSynth(const SineSynth(), channel: 1);
      synth.dispose();
      expect(gateway.last!.calls, isNot(contains('dispose:sound')));
      expect(gateway.last!.calls, contains('dispose:synth'));
    });

    test('dispose is idempotent', () {
      gateway.materialiseSynth(const SineSynth(), channel: 1)
        ..dispose()
        ..dispose();
      expect(
        gateway.last!.calls.where((c) => c == 'dispose:synth'),
        hasLength(1),
      );
    });
  });

  group('transport connections', () {
    test('connecting an internal synth to a session transport', () {
      final synth = gateway.materialiseSynth(const SineSynth(), channel: 1);
      final transport = FakeMidiTransport();

      transport.connectSynth(synth);
      expect(transport.connectedSynths, [synth]);
      expect(transport.calls, contains('connectSynth'));

      transport.disconnectSynth(synth);
      expect(transport.connectedSynths, isEmpty);
    });

    test('connecting the external MIDI-out port', () {
      final transport = FakeMidiTransport();
      transport.connectMidiOut();
      expect(transport.midiOutConnected, isTrue);
      transport.disconnectMidiOut();
      expect(transport.midiOutConnected, isFalse);
    });
  });
}
