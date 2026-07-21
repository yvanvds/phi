/// The static method table the completion popup offers one level past an entity
/// (`voice.bells.` → these verbs) — design `docs/design/live-coding.md` §6.
///
/// **A checked-in artifact derived from the `phi` library source.** These are
/// exactly the verb names `python/phi/__init__.py` exposes through `_VERB_NAMES`
/// (what in-script `dir(voice.bells)` lists), copied here so the editor needs no
/// Python analysis at completion time. The two must never drift: the drift-guard
/// test `test/domain/code/completion/phi_method_table_drift_test.dart` fails when
/// this list and the library's `_VERB_NAMES` diverge, printing the corrected list
/// to paste back here.
///
/// Order matches `_VERB_NAMES`, so the popup offers verbs in the library's own
/// order. Insertion is always the bare name — a method row inserts `note`, never
/// `note(...)` (design §6: "inserts the identifier only").
const List<String> phiMethodTable = <String>[
  'play',
  'stop',
  'pause',
  'loop',
  'note',
  'off',
  'fire',
  'set',
  'send',
  'fade',
];
