import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_creation_args.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

/// The `~dac` catalogue fallback (issue #434).
///
/// The engine can *create* a `~dac` (`CreateObject` special-cases it) but its
/// metadata registry never lists the type, so the catalogue the palette and
/// inline object box complete against omitted it — the one object every
/// audible patch needs could not be created by hand. [RealPatcherGateway]
/// appends a hand-authored descriptor when (and only when) the engine's own
/// metadata lacks the type; the merge is a static seam so it is testable
/// without `libyse.dll` (the real `objectTypes()` needs the engine's live
/// registry, verified by hand like the rest of the real gateway).
void main() {
  const sine = PatchObjectDescriptor(
    type: Obj.dSine,
    description: 'sine oscillator',
    category: PatchObjectCategory.oscillator,
    isDsp: true,
    inlets: [],
    outlets: [],
    params: [],
  );

  group('RealPatcherGateway.withDacFallback', () {
    test('appends ~dac to a catalogue the engine metadata omitted it from', () {
      final merged = RealPatcherGateway.withDacFallback(const [sine]);

      expect(merged.map((d) => d.type), [Obj.dSine, Obj.dDac]);
      expect(merged.last, same(RealPatcherGateway.dacDescriptor));
    });

    test('adds ~dac even to an empty catalogue', () {
      final merged = RealPatcherGateway.withDacFallback(const []);
      expect(merged.map((d) => d.type), [Obj.dDac]);
    });

    test('leaves a catalogue that already documents ~dac untouched — an '
        'engine that ships the metadata wins outright', () {
      const engineDac = PatchObjectDescriptor(
        type: Obj.dDac,
        description: 'the engine’s own dac docs',
        category: PatchObjectCategory.generic,
        isDsp: true,
        inlets: [],
        outlets: [],
        params: [],
      );

      final merged = RealPatcherGateway.withDacFallback(const [
        sine,
        engineDac,
      ]);

      expect(merged.map((d) => d.type), [Obj.dSine, Obj.dDac]);
      expect(merged, isNot(contains(RealPatcherGateway.dacDescriptor)));
      expect(merged.last.description, engineDac.description);
    });
  });

  group('RealPatcherGateway.dacDescriptor', () {
    const dac = RealPatcherGateway.dacDescriptor;

    test('describes the sink the engine actually builds', () {
      expect(dac.type, Obj.dDac);
      expect(dac.isDsp, isTrue);
      // A stereo sink: two audio inlets, nothing downstream.
      expect(dac.inlets, hasLength(2));
      expect(dac.inlets.every((i) => i.isDspInput), isTrue);
      expect(dac.outlets, isEmpty);
    });

    test('is typable: a bare `dac` line passes the creation-args gate', () {
      // No documented params — the engine constructs a ~dac from the
      // patcher's channel count and takes no arguments.
      expect(dac.params, isEmpty);

      final noArgs = PatchCreationArgs.check(dac, '');
      expect(noArgs.isValid, isTrue);
      expect(noArgs.args, isEmpty);

      // And handing it arguments is refused before anything is minted.
      final withArgs = PatchCreationArgs.check(dac, '3');
      expect(withArgs.isValid, isFalse);
      expect(withArgs.problem, contains('takes no arguments'));
    });
  });
}
