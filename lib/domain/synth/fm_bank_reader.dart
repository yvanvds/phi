/// Reads the patch names out of a DX7 `.syx` bank so the racks FM editor can
/// browse them (design `docs/design/racks-and-voices.md` §4, §8 — "FM: … patch
/// list from `patchCount`/`patchName`").
///
/// A pure-domain seam: the FM editor holds one and asks it for the names of the
/// bank a definition references, without ever touching `package:yse`. The same
/// Real/Fake split as [AssetImporter] — the production reader lives in
/// `lib/engine/bridge/` over `Dx7Bank`, and tests inject a fake that returns
/// canned names (the "populating from a fake bank" the issue's *Done when*
/// calls for).
abstract interface class FmBankReader {
  /// The patch names in the bank at [bankRef] (a project-relative `.syx` asset
  /// path), in bank order. Returns an empty list when [bankRef] is `null` or the
  /// bank cannot be read — the editor then shows its "no bank" state rather than
  /// failing.
  List<String> patchNames(String? bankRef);
}
