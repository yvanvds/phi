import '../patch_type_name.dart';

/// The file-name rule for a tutorial (issue #489): which `<slug>.phitut.json`
/// a type's tutorial is stored under.
///
/// A canonical type id cannot be a file name — `~`, `.`, `!`, `/` and `|` are
/// all in play (`.!=`, `~/`, `.||`) — so the slug is:
///
/// - the bare name ([PatchTypeName.bare]) — `.metro` → `metro`;
/// - an operator spelled out — `.!=` → `neq`, `.+` → `plus`;
/// - `sig-` in front of a `~` type whose bare name a control type also has —
///   `~+` → `sig-plus`, `~line` → `sig-line` (but `~sine` → `sine`);
/// - any other character outside `[a-z0-9-]` folded to `-` — `.array.at` →
///   `array-at`.
///
/// The index (`index.json`) is what the app actually reads, so a tutorial
/// covering several types simply has several index entries pointing at one
/// slug; this rule is what an author (and the export command) names a new
/// file by, and what the asset test holds single-type entries to.
abstract final class TutorialSlug {
  /// Spelled-out operator names, keyed by the bare operator.
  static const Map<String, String> operators = {
    '+': 'plus',
    '-': 'minus',
    '*': 'times',
    '/': 'divide',
    '%': 'mod',
    '!-': 'rminus',
    '!/': 'rdivide',
    '==': 'eq',
    '!=': 'neq',
    '<': 'lt',
    '<=': 'lte',
    '>': 'gt',
    '>=': 'gte',
    '&&': 'and',
    '||': 'or',
    '&': 'bitand',
    '|': 'bitor',
    '<<': 'shl',
    '>>': 'shr',
  };

  /// The slug for [type]. [knownTypes] is the engine catalogue, consulted only
  /// for the `sig-` clash rule; without it a `~` type never gets the prefix.
  static String of(String type, {Iterable<String> knownTypes = const []}) {
    final bare = PatchTypeName.bare(type);
    var slug = operators[bare] ?? bare.toLowerCase();
    slug = slug.replaceAll(RegExp('[^a-z0-9-]+'), '-');
    slug = slug.replaceAll(RegExp('-+'), '-');
    slug = slug.replaceAll(RegExp(r'^-|-$'), '');
    if (slug.isEmpty) slug = 'object';
    if (PatchTypeName.isDsp(type) && knownTypes.contains('.$bare')) {
      slug = 'sig-$slug';
    }
    return slug;
  }
}
