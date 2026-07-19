/// A small, stable bucket derived from a note's `voice.` address — the display
/// handle scene keying and voice colouring fold a voice into (design
/// `docs/design/racks-and-voices.md` §6, "colour by routed voice").
///
/// A voice is an address string, but the Scene field keys agents by a small int
/// and the six-swatch palette colours by an index. This folds any voice address
/// into a **deterministic** non-negative int so the same voice always keys and
/// colours the same way — across runs, not just within one (Dart's `hashCode`
/// is not guaranteed stable between isolates). `null` or empty (an unrouted
/// note) folds to `0`, matching the old channel-0 default.
int voiceHash(String? voice) {
  if (voice == null || voice.isEmpty) return 0;
  var h = 0;
  for (var i = 0; i < voice.length; i++) {
    h = (h * 31 + voice.codeUnitAt(i)) & 0x1fffffff;
  }
  return h;
}
