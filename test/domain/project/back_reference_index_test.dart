import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/back_reference_index.dart';
import 'package:phi/domain/project/entity_address.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  late BackReferenceIndex index;

  setUp(() => index = BackReferenceIndex());

  test('records forward and reverse edges', () {
    index.add(addr('voice.bells'), [addr('synth.fm_bells'), addr('mix.perc')]);

    expect(index.referencesOf(addr('voice.bells')), {
      addr('synth.fm_bells'),
      addr('mix.perc'),
    });
    expect(index.referrersOf(addr('mix.perc')), {addr('voice.bells')});
    expect(index.referrersOf(addr('synth.fm_bells')), {addr('voice.bells')});
    expect(index.hasReferrers(addr('mix.perc')), isTrue);
  });

  test('several sources can reference one target', () {
    index.add(addr('voice.bells'), [addr('mix.perc')]);
    index.add(addr('voice.tom'), [addr('mix.perc')]);
    expect(index.referrersOf(addr('mix.perc')), {
      addr('voice.bells'),
      addr('voice.tom'),
    });
  });

  test('removeSource drops outgoing edges but leaves incoming ones', () {
    index.add(addr('voice.bells'), [addr('mix.perc')]);
    index.add(addr('mix.perc'), [addr('mix.master')]);

    // Remove voice.bells as a source: it stops referencing mix.perc …
    index.removeSource(addr('voice.bells'));
    expect(index.referencesOf(addr('voice.bells')), isEmpty);
    expect(index.referrersOf(addr('mix.perc')), isEmpty);
    // … but mix.perc's own outgoing edge to mix.master survives.
    expect(index.referrersOf(addr('mix.master')), {addr('mix.perc')});
  });

  test('removeSource of an unknown source is a no-op', () {
    index.add(addr('voice.bells'), [addr('mix.perc')]);
    index.removeSource(addr('voice.ghost'));
    expect(index.referrersOf(addr('mix.perc')), {addr('voice.bells')});
  });

  test('empty targets record nothing', () {
    index.add(addr('voice.bells'), const []);
    expect(index.referencesOf(addr('voice.bells')), isEmpty);
    expect(index.hasReferrers(addr('voice.bells')), isFalse);
  });

  test('queries return defensive copies safe to mutate', () {
    index.add(addr('voice.bells'), [addr('mix.perc')]);
    final referrers = index.referrersOf(addr('mix.perc'))..clear();
    expect(referrers, isEmpty);
    // The index itself is untouched by mutating the returned set.
    expect(index.referrersOf(addr('mix.perc')), {addr('voice.bells')});
  });

  test('clear forgets every edge', () {
    index.add(addr('voice.bells'), [addr('mix.perc')]);
    index.clear();
    expect(index.referrersOf(addr('mix.perc')), isEmpty);
    expect(index.referencesOf(addr('voice.bells')), isEmpty);
  });
}
