import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';

void main() {
  group('SpeakerLayout', () {
    test('defaults to auto', () {
      expect(SpeakerLayout.defaultLayout, SpeakerLayout.auto);
    });

    test('wireName round-trips every case through fromWire', () {
      for (final layout in SpeakerLayout.values) {
        expect(SpeakerLayout.fromWire(layout.wireName), layout);
      }
    });

    test('uses hand-editable tokens for the surround cases', () {
      expect(SpeakerLayout.surround51.wireName, '5.1');
      expect(SpeakerLayout.surround51Side.wireName, '5.1side');
      expect(SpeakerLayout.surround61.wireName, '6.1');
      expect(SpeakerLayout.surround71.wireName, '7.1');
    });

    test('fromWire falls back to the default on missing or unknown tokens', () {
      expect(SpeakerLayout.fromWire(null), SpeakerLayout.auto);
      expect(SpeakerLayout.fromWire('surround51'), SpeakerLayout.auto);
      expect(SpeakerLayout.fromWire(7), SpeakerLayout.auto);
    });
  });
}
