import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/builtin_transform_catalog.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';

void main() {
  group('BuiltinTransformCatalog', () {
    const sample = [
      MidiNote(pitch: 60, start: 0, duration: 0.5, velocity: 0.7),
      MidiNote(pitch: 64, start: 1, duration: 0.5, velocity: 0.4),
    ];

    test('every entry builds an active transform matching its kind + name', () {
      for (final entry in BuiltinTransformCatalog.entries) {
        final t = entry.build();
        expect(t.kind, entry.kind, reason: '${entry.name} kind');
        expect(t.label, entry.name, reason: '${entry.name} label');
        expect(t.active, isTrue, reason: '${entry.name} active');
      }
    });

    test('the same entry added twice yields independently toggleable chips', () {
      // Const-built defaults may canonicalise to one object, so identity isn't
      // guaranteed — what matters is that two chips from one entry toggle
      // independently in a chain (setActiveAt keys on index, not identity).
      final entry = BuiltinTransformCatalog.entries.first;
      final chain = MidiTransformChain(
        source: MidiClip(notes: sample, bars: 1),
        transforms: [entry.build(), entry.build()],
      );
      chain.setActiveAt(0, false);
      expect(chain.transforms[0].active, isFalse);
      expect(chain.transforms[1].active, isTrue);
      chain.dispose();
    });

    test('covers all four families', () {
      for (final kind in MidiTransformKind.values) {
        expect(
          BuiltinTransformCatalog.forKind(kind),
          isNotEmpty,
          reason: 'family ${kind.tag} has no built-ins',
        );
      }
      // forKind partitions entries with none lost or duplicated.
      final total = MidiTransformKind.values
          .map((k) => BuiltinTransformCatalog.forKind(k).length)
          .fold(0, (a, b) => a + b);
      expect(total, BuiltinTransformCatalog.entries.length);
    });

    test('callback/table-driven defaults are passthrough (identity)', () {
      // Their zero-config default must leave the clip untouched — the chip
      // appears and toggles, but does nothing until its params are edited.
      const passthrough = {
        'spectral · map',
        'route',
        'split',
        'vel → param',
        'spawn · agent',
        'mute · if',
      };
      for (final entry in BuiltinTransformCatalog.entries) {
        if (!passthrough.contains(entry.name)) continue;
        expect(
          entry.build().apply(sample),
          sample,
          reason: '${entry.name} should pass notes through unchanged',
        );
      }
    });

    test('scalar defaults actually transform the clip', () {
      // A representative sensible-default (transpose +12) is not a no-op.
      final transpose = BuiltinTransformCatalog.entries
          .firstWhere((e) => e.name == 'transpose · +12 st')
          .build();
      expect(transpose.apply(sample).map((n) => n.pitch), [72, 76]);
    });
  });
}
