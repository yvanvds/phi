import 'name_problem.dart';

/// The one shared rule for what may name an entity or group in the project
/// registry — design `docs/design/project-registry.md` §3.
///
/// A single validator, reused by every create/rename dialog and by live code
/// that mints entities, so the constraint is defined exactly once. A name is a
/// single path *segment* (no dots — those separate segments in an
/// [EntityAddress]); the same string is used identically as a Python attribute,
/// a registry key, and a file name, which is what the rules below buy:
///
/// - **Pure ASCII lowercase `snake_case`** (`[a-z_][a-z0-9_]*`, max 64) — a
///   valid Python identifier that is safe on any filesystem.
/// - **Not a Python keyword** — keywords cannot follow a dot in Python source.
/// - **Not a Windows reserved device name** — `con.json` and friends misbehave.
///
/// Case-insensitive sibling uniqueness and the group/entity name clash are
/// *tree* constraints and live on the registry, not here: this validator judges
/// a name in isolation, with no knowledge of what already exists.
abstract final class NameValidator {
  /// The maximum length of a single name segment, in characters.
  static const int maxLength = 64;

  static final RegExp _pattern = RegExp(r'^[a-z_][a-z0-9_]*$');

  /// Python 3 reserved keywords that can appear as an all-lowercase name.
  ///
  /// `False`, `None` and `True` are omitted deliberately: they are not
  /// lowercase, so their lowercase spellings (`false`, `none`, `true`) are
  /// ordinary identifiers, not keywords. Soft keywords (`match`, `case`,
  /// `type`, `_`) are likewise valid identifiers and intentionally allowed.
  static const Set<String> _pythonKeywords = {
    'and',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'class',
    'continue',
    'def',
    'del',
    'elif',
    'else',
    'except',
    'finally',
    'for',
    'from',
    'global',
    'if',
    'import',
    'in',
    'is',
    'lambda',
    'nonlocal',
    'not',
    'or',
    'pass',
    'raise',
    'return',
    'try',
    'while',
    'with',
    'yield',
  };

  /// Windows reserved device names (case-insensitive on Windows, but names are
  /// forced lowercase here so a lowercase set suffices).
  static const Set<String> _reservedDeviceNames = {
    'con',
    'prn',
    'aux',
    'nul',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
  };

  /// Returns the first [NameProblem] with [name], or `null` when [name] is a
  /// valid segment. Checks run cheapest-first: emptiness, length, shape, then
  /// the keyword and reserved-name look-ups (both of which assume a
  /// well-formed lowercase token).
  static NameProblem? check(String name) {
    if (name.isEmpty) return NameProblem.empty;
    if (name.length > maxLength) return NameProblem.tooLong;
    if (!_pattern.hasMatch(name)) return NameProblem.malformed;
    if (_pythonKeywords.contains(name)) return NameProblem.pythonKeyword;
    if (_reservedDeviceNames.contains(name)) {
      return NameProblem.reservedDeviceName;
    }
    return null;
  }

  /// Whether [name] is a valid segment. Shorthand for `check(name) == null`.
  static bool isValid(String name) => check(name) == null;
}
