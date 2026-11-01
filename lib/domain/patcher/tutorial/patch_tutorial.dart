import '../patch_payload.dart';

/// One bundled **patcher tutorial** (issue #489): a small patch that demos an
/// object type's key features and explains them in its own notes.
///
/// Stored as `assets/tutorials/patcher/<slug>.phitut.json`:
///
/// ```json
/// {"title": "metro", "covers": [".metro"], "summary": "…",
///  "payload": {"dump": {…}, "placement": "mix.master"}}
/// ```
///
/// [payload] is an ordinary [PatchPayload] — the engine `dumpJson` plus an
/// optional placement — so a tutorial is built in Phi itself and opens through
/// the same `parseJson` path a saved patch does. [covers] lists the canonical
/// type ids it teaches (`.metro`, `~sine`, `.!=`): one tutorial may cover
/// several (`.umenu` / `.radiogroup` / `.tab`).
///
/// Pure Dart: parsing and encoding only. Loading the asset is the engine's job.
class PatchTutorial {
  const PatchTutorial({
    required this.title,
    required this.covers,
    required this.payload,
    this.summary = '',
  });

  /// Reads a tutorial from its decoded JSON. Throws a [FormatException] when
  /// `title` is missing or `payload` is not a map — a malformed bundled file is
  /// a packaging bug, and the asset test should name it.
  factory PatchTutorial.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('a tutorial needs a non-empty "title"');
    }
    final payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException('a tutorial needs a "payload" map');
    }
    final covers = json['covers'];
    final summary = json['summary'];
    return PatchTutorial(
      title: title,
      covers: [
        if (covers is List)
          for (final c in covers)
            if (c is String) c,
      ],
      summary: summary is String ? summary : '',
      payload: PatchPayload.fromJson(payload.cast<String, Object?>()),
    );
  }

  /// The heading shown in the tutorial banner.
  final String title;

  /// The canonical type ids this tutorial teaches.
  final List<String> covers;

  /// One or two sentences on what the tutorial shows.
  final String summary;

  /// The patch itself: engine dump plus optional placement.
  final PatchPayload payload;

  /// The tutorial as JSON — the `.phitut.json` file format.
  Map<String, Object?> toJson() => {
    'title': title,
    'covers': covers,
    'summary': summary,
    'payload': payload.toJson(),
  };
}
