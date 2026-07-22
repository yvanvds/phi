import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';
import 'package:phi/engine/state/audition_voice_control_port.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// The real `voice` leg of the control plane (issue #334): a decoded
/// `phi.ctl.voice.<name>.note` / `.off` drives the racks audition path through
/// [EngineMidiController], with the port tracking held notes so a bare `off()`
/// releases everything the voice is holding.
///
/// The audition path is exercised through an **external** voice so each note
/// lands as an observable `sendNoteOn` / `sendNoteOff` on the [FakeMidiGateway]
/// (an internal voice would need a materialised synth the racks epic provides).
void main() {
  late FakeMidiGateway gateway;
  late EngineMidiController midi;
  late AuditionVoiceControlPort port;

  final bells = EntityAddress.parse('voice.bells');

  setUp(() {
    gateway = FakeMidiGateway();
    midi = EngineMidiController(chain: defaultDemoChain(), gateway: gateway)
      // Map `voice.bells` to external MIDI channel 1 (→ transport channel 0),
      // so audition sounds it straight out the port.
      ..voiceResolver = const VoiceChannelResolver(
        externalChannels: {'voice.bells': 1},
      );
    port = AuditionVoiceControlPort(midi);
  });

  tearDown(() async {
    midi.dispose();
    await gateway.dispose();
  });

  test('note sounds the voice immediately at the given velocity', () {
    port.note(bells, pitch: 60, velocity: 90);
    expect(gateway.calls, contains('sendNoteOn:0:60:90'));
  });

  test('note defaults to velocity 100', () {
    port.note(bells, pitch: 62);
    expect(gateway.calls, contains('sendNoteOn:0:62:100'));
  });

  test('off with a pitch releases just that note', () {
    port.note(bells, pitch: 60);
    port.off(bells, pitch: 60);
    expect(gateway.calls, contains('sendNoteOff:0:60'));
  });

  test('a bare off releases every note the voice is holding', () {
    port.note(bells, pitch: 60);
    port.note(bells, pitch: 64);
    port.note(bells, pitch: 67);
    gateway.calls.clear();

    port.off(bells); // no pitch → release all

    final offs = gateway.calls
        .where((c) => c.startsWith('sendNoteOff:'))
        .toSet();
    expect(offs, {'sendNoteOff:0:60', 'sendNoteOff:0:64', 'sendNoteOff:0:67'});
  });

  test('a bare off after the notes are already released does nothing', () {
    port.note(bells, pitch: 60);
    port.off(bells, pitch: 60);
    gateway.calls.clear();

    port.off(bells);

    expect(gateway.calls.where((c) => c.startsWith('sendNoteOff:')), isEmpty);
  });
}
