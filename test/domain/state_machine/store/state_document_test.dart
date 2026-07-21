import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/state_slices.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_transition_spec.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';

void main() {
  final verse = EntityAddress.parse('state.verse');
  final chorus = EntityAddress.parse('state.chorus');
  final drums = EntityAddress.parse('clip.drums');
  final pads = EntityAddress.parse('mix.pads');
  final drum = EntityAddress.parse('domain.drum');
  final enterScript = EntityAddress.parse('code.on_intro');

  StateDocument fullDocument() => StateDocument(
    position: const Offset(160, 160),
    transitions: [
      StateTransitionSpec(to: verse, label: 'drop'),
      StateTransitionSpec(
        to: chorus,
        trigger: TimedTrigger(beats: 16, domain: drum),
      ),
    ],
    slices: StateSlices(
      clips: [ClipSliceEntry(clip: drums)],
      mix: [MixSliceEntry(bus: pads, volume: 0.4, muted: true)],
      variables: const {'section': 'a'},
      tempos: [TempoSliceEntry(domain: drum, bpm: 124)],
    ),
    onEnter: enterScript,
  );

  group('StateDocument JSON round-trip', () {
    test('a full document round-trips identity (issue #240 done-when)', () {
      final document = fullDocument();
      final decoded = StateDocument.fromJson(document.toJson());
      expect(decoded, document);
      // Byte-identical through a JSON encode as well — the on-disk form.
      expect(jsonEncode(decoded.toJson()), jsonEncode(document.toJson()));
    });

    test('a minimal document stays minimal', () {
      const document = StateDocument(position: Offset(400, 160));
      final json = document.toJson();
      expect(json.containsKey('slices'), isFalse);
      expect(json.containsKey('onEnter'), isFalse);
      expect(StateDocument.fromJson(json), document);
    });

    test('transition order is preserved — transitions are ordered', () {
      final document = fullDocument();
      final decoded = StateDocument.fromJson(document.toJson());
      expect(decoded.transitions.map((t) => t.to), [verse, chorus]);
    });

    test('an empty map decodes to defaults', () {
      final decoded = StateDocument.fromJson(const {});
      expect(decoded.position, Offset.zero);
      expect(decoded.transitions, isEmpty);
      expect(decoded.slices.isEmpty, isTrue);
      expect(decoded.onEnter, isNull);
    });

    test('a malformed transition target throws', () {
      expect(
        () => StateDocument.fromJson(const {
          'transitions': [
            {'to': 'not an address'},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('StateDocument references', () {
    test('collects transition targets, trigger domains, slice entries and '
        'the on-enter ref', () {
      expect(fullDocument().references, {
        verse,
        chorus,
        drum, // both the timed trigger's and the tempo slice's domain
        drums,
        pads,
        enterScript,
      });
    });

    test('a bare document references nothing', () {
      expect(const StateDocument().references, isEmpty);
    });

    test('withReferenceUpdated repoints a transition target and round-trips '
        'through the inverse', () {
      final renamed = EntityAddress.parse('state.bridge');
      final document = fullDocument();
      final repointed = document.withReferenceUpdated(verse, renamed);
      expect(repointed.transitions.first.to, renamed);
      expect(repointed.references, isNot(contains(verse)));
      expect(repointed.references, contains(renamed));
      expect(repointed.withReferenceUpdated(renamed, verse), document);
    });

    test('withReferenceUpdated repoints the on-enter script', () {
      final renamed = EntityAddress.parse('code.intro_enter');
      final repointed = fullDocument().withReferenceUpdated(
        enterScript,
        renamed,
      );
      expect(repointed.onEnter, renamed);
    });

    test('withReferenceUpdated repoints slice entries', () {
      final renamed = EntityAddress.parse('mix.synths');
      final repointed = fullDocument().withReferenceUpdated(pads, renamed);
      expect(repointed.slices.mix!.single.bus, renamed);
    });
  });

  group('StateDocument copyWith', () {
    test('replaces fields and clears the on-enter ref explicitly', () {
      final document = fullDocument();
      final moved = document.copyWith(position: const Offset(0, 32));
      expect(moved.position, const Offset(0, 32));
      expect(moved.transitions, document.transitions);

      final cleared = document.copyWith(clearOnEnter: true);
      expect(cleared.onEnter, isNull);
      // A plain copy keeps it.
      expect(document.copyWith().onEnter, enterScript);
    });
  });
}
