import 'package:yse/yse.dart';

import '../../domain/synth/fm_bank_reader.dart';
import 'real_materialised_synth.dart' show AssetPathResolver;

/// Production [FmBankReader] backed by `package:yse`'s [Dx7Bank] (design
/// `docs/design/racks-and-voices.md` §4).
///
/// Resolves the definition's project-relative `.syx` ref to an absolute path
/// through the shared [AssetPathResolver] (the same seam
/// [RealMaterialisedSynth] uses), loads the bank, and reads its
/// `patchCount`/`patchName`. Every failure — no ref, an unreadable or malformed
/// bank — is swallowed into an empty list so the editor degrades to its "no
/// bank" state instead of throwing; the bank is disposed straight after reading
/// (the names are copied out).
class Dx7FmBankReader implements FmBankReader {
  /// Builds a reader that resolves refs through [resolveAsset] (defaults to the
  /// identity, for a caller that already hands absolute paths).
  Dx7FmBankReader({AssetPathResolver? resolveAsset})
    : _resolveAsset = resolveAsset ?? _identity;

  static String _identity(String ref) => ref;

  final AssetPathResolver _resolveAsset;

  @override
  List<String> patchNames(String? bankRef) {
    if (bankRef == null) return const [];
    Dx7Bank? bank;
    try {
      bank = Dx7Bank.load(_resolveAsset(bankRef));
      return [for (var i = 0; i < bank.patchCount; i++) bank.patchName(i)];
    } on YseException {
      return const [];
    } finally {
      bank?.dispose();
    }
  }
}
