/// The bundled tutorial **index** (issue #489): which object types have a
/// tutorial, and under which slug.
///
/// Read from `assets/tutorials/patcher/index.json`, a flat JSON object keyed
/// by the **canonical** type id:
///
/// ```json
/// {".metro": "metro", ".umenu": "menus", ".radiogroup": "menus"}
/// ```
///
/// Several types may share one slug (one tutorial covering a family). This is
/// what the UI asks — [hasTutorial] gates the reference panel's "Open
/// tutorial" button and the browser's entries, [tutorialFor] names the file to
/// load — so content can be added without touching code.
///
/// Pure Dart: it parses the index string; loading it is the engine's job.
class TutorialCatalog {
  /// A catalog over an already-decoded [entries] map (type → slug).
  TutorialCatalog(Map<String, String> entries)
    : _entries = Map.unmodifiable(entries);

  /// Parses a decoded `index.json`. Entries whose value is not a non-empty
  /// string are skipped rather than failing the whole index.
  factory TutorialCatalog.fromJson(Map<String, Object?> json) =>
      TutorialCatalog({
        for (final e in json.entries)
          if (e.value is String && (e.value as String).trim().isNotEmpty)
            e.key: (e.value as String).trim(),
      });

  /// A catalog with no tutorials — what the UI sees before the index loads,
  /// or when it could not be read.
  static final TutorialCatalog empty = TutorialCatalog(const {});

  /// The asset folder every tutorial file and the index live in.
  static const String assetDir = 'assets/tutorials/patcher';

  /// The index's asset path.
  static const String indexPath = '$assetDir/index.json';

  /// The file extension of one tutorial.
  static const String extension = '.phitut.json';

  /// The asset path of the tutorial stored under [slug].
  static String assetPathFor(String slug) => '$assetDir/$slug$extension';

  final Map<String, String> _entries;

  /// Every type → slug entry, in index order.
  Map<String, String> get entries => _entries;

  /// Every type with a tutorial.
  Iterable<String> get types => _entries.keys;

  /// Every distinct slug the index points at.
  Set<String> get slugs => _entries.values.toSet();

  /// Whether the catalog has no entries.
  bool get isEmpty => _entries.isEmpty;

  /// Whether [type] (canonical id) has a tutorial.
  bool hasTutorial(String type) => _entries.containsKey(type);

  /// The slug of [type]'s tutorial, or null when it has none.
  String? tutorialFor(String type) => _entries[type];

  /// The types the tutorial stored under [slug] is indexed for.
  List<String> typesFor(String slug) => [
    for (final e in _entries.entries)
      if (e.value == slug) e.key,
  ];
}
