import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/domain_clock_publisher.dart';

import '../test_doubles/fake_patch_clock.dart';

/// The publisher keeps one engine clock per time domain, named by the
/// domain's address and paced at its played tempo (issue #529).
void main() {
  EntityAddress domain(String name) =>
      EntityAddress(kind: RegistryKinds.domain, segments: [name]);

  late Map<EntityAddress, double> tempos;
  late List<FakePatchClock> published;
  late Set<String> claimed;
  late DomainClockPublisher publisher;

  setUp(() {
    tempos = {domain('drum'): 124, domain('pad'): 90};
    published = [];
    claimed = {};
    publisher = DomainClockPublisher(
      publish: (name, tempo) {
        if (claimed.contains(name)) return null;
        final clock = FakePatchClock(name, tempo: tempo);
        published.add(clock);
        return clock;
      },
      domains: () => tempos.keys,
      tempoOf: (d) => tempos[d],
    );
  });

  FakePatchClock clock(String name) =>
      publisher.clockOf(domain(name))! as FakePatchClock;

  test('names each clock by its domain\'s address', () {
    expect(DomainClockPublisher.clockNameFor(domain('drum')), 'domain.drum');
  });

  test('publishes a clock per domain at its tempo', () {
    publisher.sync();
    expect(publisher.clockNames, ['domain.drum', 'domain.pad']);
    expect(clock('drum').tempos, [124]);
    expect(clock('pad').tempos, [90]);
  });

  test('pushes a changed tempo, and only a changed one', () {
    publisher.sync();
    publisher.sync();
    expect(clock('drum').tempos, [124], reason: 'nothing changed');
    tempos[domain('drum')] = 100;
    publisher.sync();
    expect(clock('drum').tempos, [124, 100]);
    expect(clock('pad').tempos, [90]);
  });

  test('a removed domain\'s clock is destroyed; a new one is published', () {
    publisher.sync();
    final drum = clock('drum');
    tempos.remove(domain('drum'));
    tempos[domain('bass')] = 60;
    publisher.sync();
    expect(drum.disposed, isTrue);
    expect(publisher.clockOf(domain('drum')), isNull);
    expect(clock('bass').tempos, [60]);
  });

  test('a name a patch claimed first is left alone, and not retried', () {
    claimed.add('domain.drum');
    publisher.sync();
    publisher.sync();
    expect(publisher.clockOf(domain('drum')), isNull);
    expect(published.map((c) => c.name), ['domain.pad']);
  });

  test('release destroys every clock; the next sync publishes them again', () {
    publisher.sync();
    final first = [...published];
    publisher.release();
    expect(first.every((c) => c.disposed), isTrue);
    expect(publisher.clockNames, isEmpty);
    publisher.sync();
    expect(published, hasLength(4));
    expect(clock('drum').disposed, isFalse);
  });
}
