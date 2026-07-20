import 'patch_object_descriptor.dart';

/// Whether an outlet emitting [outletType] may legally feed an inlet whose
/// accepted-message mask is [accepts] (design `docs/design/patcher.md` §6,
/// "inlets light up only when compatible — `accepts` mask + `isDspInput`").
///
/// The rule mirrors YSE's own typing: a DSP/audio signal (a `buffer` outlet)
/// may only enter an audio inlet (one that accepts a `buffer`, i.e.
/// [PatchInletDescriptor.isDspInput]); a control message may only enter an
/// inlet that accepts that message kind. `float` and `integer` are treated as
/// interchangeable (YSE coerces between them), and an `any` outlet feeds any
/// inlet that accepts anything at all. An `invalid` outlet — or an inlet that
/// accepts nothing — is never compatible.
///
/// This gates the *authoring gesture* only: it decides which inlets light up
/// during a cable drag and whether a drop is accepted. The controller's
/// low-level `connect` stays permissive (YSE inlets are polymorphic and the
/// native side ignores what it can't consume), so the seed and any programmatic
/// wiring are unaffected.
bool patchPinsCompatible(
  PatchOutletType outletType,
  Set<PatchInletAccept> accepts,
) {
  switch (outletType) {
    case PatchOutletType.invalid:
      return false;
    case PatchOutletType.buffer:
      return accepts.contains(PatchInletAccept.buffer);
    case PatchOutletType.bang:
      return accepts.contains(PatchInletAccept.bang);
    case PatchOutletType.float:
    case PatchOutletType.integer:
      return accepts.contains(PatchInletAccept.float) ||
          accepts.contains(PatchInletAccept.integer);
    case PatchOutletType.list:
      return accepts.contains(PatchInletAccept.list);
    case PatchOutletType.any:
      return accepts.isNotEmpty;
  }
}
