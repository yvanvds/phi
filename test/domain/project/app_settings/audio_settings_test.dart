import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/app_settings/speaker_layout.dart';

void main() {
  group('AudioSettings', () {
    test(
      'defaults to the platform device with no overrides and auto layout',
      () {
        const audio = AudioSettings();
        expect(audio.outputHost, isNull);
        expect(audio.outputDevice, isNull);
        expect(audio.sampleRate, isNull);
        expect(audio.bufferSize, isNull);
        expect(audio.layout, SpeakerLayout.auto);
      },
    );

    test('round-trips a fully-specified value through JSON', () {
      const audio = AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Fireface UCX',
        sampleRate: 48000,
        bufferSize: 256,
        layout: SpeakerLayout.surround51,
      );
      expect(AudioSettings.fromJson(audio.toJson()), audio);
    });

    test('round-trips the all-default value through JSON', () {
      const audio = AudioSettings();
      expect(AudioSettings.fromJson(audio.toJson()), audio);
    });

    test('omits absent overrides from JSON (absent = device default)', () {
      const audio = AudioSettings(
        outputHost: 'WASAPI',
        outputDevice: 'Speakers',
      );
      final json = audio.toJson();
      expect(json.containsKey('sampleRate'), isFalse);
      expect(json.containsKey('bufferSize'), isFalse);
      expect(json['layout'], 'auto');
    });

    test('fromJson tolerates missing keys with defaults', () {
      final audio = AudioSettings.fromJson(const {});
      expect(audio, const AudioSettings());
    });

    test('fromJson treats malformed keys as absent', () {
      final audio = AudioSettings.fromJson(const {
        'outputHost': 42,
        'outputDevice': ['nope'],
        'sampleRate': 'fast',
        'bufferSize': -128,
        'layout': 'bogus',
      });
      expect(audio.outputHost, isNull);
      expect(audio.outputDevice, isNull);
      expect(audio.sampleRate, isNull);
      // A non-positive buffer size is treated as absent.
      expect(audio.bufferSize, isNull);
      expect(audio.layout, SpeakerLayout.auto);
    });

    test('value equality and hashCode by fields', () {
      const a = AudioSettings(outputDevice: 'X', sampleRate: 44100);
      const b = AudioSettings(outputDevice: 'X', sampleRate: 44100);
      const c = AudioSettings(outputDevice: 'X', sampleRate: 48000);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
