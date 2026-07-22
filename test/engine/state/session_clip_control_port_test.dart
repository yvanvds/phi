import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';
import 'package:phi/engine/state/session_clip_control_port.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// The real `clip` leg of the control plane (issue #334): a decoded
/// `phi.ctl.clip.*` verb drives the [EngineMidiController] session manager,
/// including the **open-from-registry** step for a clip with no open session.
void main() {
  late FakeMidiGateway gateway;
  late EngineMidiController midi;
  late Map<EntityAddress, ClipDocument> docs;
  late SessionClipControlPort port;

  final clipA = EntityAddress.parse('clip.phrase_a');

  ClipDocument buildDoc() => ClipDocument(source: phraseA());

  setUp(() {
    gateway = FakeMidiGateway();
    midi = EngineMidiController(chain: defaultDemoChain(), gateway: gateway);
    docs = {clipA: buildDoc()};
    port = SessionClipControlPort(midi: midi, documentAt: (a) => docs[a]);
  });

  tearDown(() async {
    midi.dispose();
    await gateway.dispose();
  });

  test('play opens a clip from the registry when no session is open', () {
    expect(midi.sessionFor(clipA), isNull);

    port.play(clipA);

    final session = midi.sessionFor(clipA);
    expect(session, isNotNull);
    expect(session!.isPlaying, isTrue);
  });

  test('play reuses an already-open session rather than re-opening', () {
    final opened = midi.ensureSession(clipA, buildDoc());
    port.play(clipA);
    expect(identical(midi.sessionFor(clipA), opened), isTrue);
    expect(opened.isPlaying, isTrue);
  });

  test('stop halts the playing session', () {
    port.play(clipA);
    expect(midi.sessionFor(clipA)!.isPlaying, isTrue);

    port.stop(clipA);
    expect(midi.sessionFor(clipA)!.isPlaying, isFalse);
  });

  test('pause freezes the playing session', () {
    port.play(clipA);
    port.pause(clipA);
    expect(midi.sessionFor(clipA)!.isPaused, isTrue);
  });

  test('loop opens the clip and sets its loop flag', () {
    port.loop(clipA, on: false);
    expect(midi.sessionFor(clipA)!.loop, isFalse);

    port.loop(clipA, on: true);
    expect(midi.sessionFor(clipA)!.loop, isTrue);
  });

  test('stopAll stops every open session', () {
    port.play(clipA);
    final other = EntityAddress.parse('clip.other');
    midi.ensureSession(other, buildDoc());
    midi.playSession(other);
    expect(midi.sessionFor(other)!.isPlaying, isTrue);

    port.stopAll();

    expect(midi.sessionFor(clipA)!.isPlaying, isFalse);
    expect(midi.sessionFor(other)!.isPlaying, isFalse);
  });

  test('an unknown clip with no document is a silent no-op', () {
    port.play(EntityAddress.parse('clip.nope'));
    expect(midi.sessionFor(EntityAddress.parse('clip.nope')), isNull);
  });

  test('a group verb acts on the already-open sessions beneath it', () {
    final kick = EntityAddress.parse('clip.drums.kick');
    midi.ensureSession(kick, buildDoc());
    midi.playSession(kick);
    expect(midi.sessionFor(kick)!.isPlaying, isTrue);

    // `clip.drums` names no session and no clip document → treated as a group.
    port.stop(EntityAddress.parse('clip.drums'));
    expect(midi.sessionFor(kick)!.isPlaying, isFalse);
  });
}
