import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/custom_transform_registry.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';

List<DslNote> _identity(List<DslNote> notes) => notes;
List<DslNote> _octaveUp(List<DslNote> notes) =>
    notes.map((n) => n.copyWith(pitch: n.pitch + 12)).toList();

void main() {
  group('CustomTransformRegistry', () {
    late CustomTransformRegistry registry;
    late int notifications;

    setUp(() {
      registry = CustomTransformRegistry();
      notifications = 0;
      registry.addListener(() => notifications++);
    });

    tearDown(() => registry.dispose());

    test('register adds a definition and notifies', () {
      final def = registry.register(
        name: 'octave up',
        kind: MidiTransformKind.pitch,
        transform: _octaveUp,
      );

      expect(def.name, 'octave up');
      expect(def.kind, MidiTransformKind.pitch);
      expect(registry.definitions.single, same(def));
      expect(registry.contains('octave up'), isTrue);
      expect(registry['octave up'], same(def));
      expect(notifications, 1);
    });

    test('re-registering the same name hot-reloads in place', () {
      final first = registry.register(name: 'x', transform: _identity);
      final second = registry.register(name: 'x', transform: _octaveUp);

      // Same definition object — chips holding it keep working.
      expect(second, same(first));
      expect(registry.definitions, hasLength(1));
      expect(registry.definitions.single, same(first));
      // The function was swapped.
      expect(first.transform, same(_octaveUp));
      expect(notifications, 2);
    });

    test('re-register keeps the original insertion slot and family', () {
      registry.register(
        name: 'a',
        kind: MidiTransformKind.pitch,
        transform: _identity,
      );
      registry.register(
        name: 'b',
        kind: MidiTransformKind.voice,
        transform: _identity,
      );
      // Re-register 'a' with a different kind arg and a new function.
      registry.register(
        name: 'a',
        kind: MidiTransformKind.struct,
        transform: _octaveUp,
      );

      // Slot order is unchanged (no jump to the end)...
      expect(registry.definitions.map((d) => d.name), ['a', 'b']);
      // ...and the original family is preserved — only the function reloads.
      expect(registry['a']!.kind, MidiTransformKind.pitch);
      expect(registry['a']!.transform, same(_octaveUp));
    });

    test('unregister removes and notifies; missing name is a no-op', () {
      registry.register(name: 'x', transform: _identity);
      notifications = 0;

      registry.unregister('nope');
      expect(notifications, 0);

      registry.unregister('x');
      expect(registry.contains('x'), isFalse);
      expect(registry.definitions, isEmpty);
      expect(notifications, 1);
    });

    test('definitions list is unmodifiable', () {
      final def = registry.register(name: 'x', transform: _identity);
      expect(() => registry.definitions.add(def), throwsUnsupportedError);
    });
  });
}
