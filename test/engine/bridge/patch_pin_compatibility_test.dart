import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patch_pin_compatibility.dart';

void main() {
  group('patchPinsCompatible', () {
    test('a signal outlet only feeds a DSP (buffer) inlet', () {
      expect(
        patchPinsCompatible(PatchOutletType.buffer, {PatchInletAccept.buffer}),
        isTrue,
      );
      expect(
        patchPinsCompatible(PatchOutletType.buffer, {PatchInletAccept.float}),
        isFalse,
      );
    });

    test('a float outlet feeds an inlet accepting float or integer', () {
      expect(
        patchPinsCompatible(PatchOutletType.float, {PatchInletAccept.float}),
        isTrue,
      );
      expect(
        patchPinsCompatible(PatchOutletType.float, {PatchInletAccept.integer}),
        isTrue,
      );
      // A float must not enter an audio-only inlet.
      expect(
        patchPinsCompatible(PatchOutletType.float, {PatchInletAccept.buffer}),
        isFalse,
      );
    });

    test('an integer outlet is interchangeable with float inlets', () {
      expect(
        patchPinsCompatible(PatchOutletType.integer, {PatchInletAccept.float}),
        isTrue,
      );
    });

    test('bang and list match only their own kind', () {
      expect(
        patchPinsCompatible(PatchOutletType.bang, {PatchInletAccept.bang}),
        isTrue,
      );
      expect(
        patchPinsCompatible(PatchOutletType.bang, {PatchInletAccept.float}),
        isFalse,
      );
      expect(
        patchPinsCompatible(PatchOutletType.list, {PatchInletAccept.list}),
        isTrue,
      );
    });

    test('an any outlet feeds any inlet that accepts something', () {
      expect(
        patchPinsCompatible(PatchOutletType.any, {PatchInletAccept.buffer}),
        isTrue,
      );
      expect(patchPinsCompatible(PatchOutletType.any, const {}), isFalse);
    });

    test('an invalid outlet is never compatible', () {
      expect(
        patchPinsCompatible(PatchOutletType.invalid, {PatchInletAccept.buffer}),
        isFalse,
      );
    });
  });
}
