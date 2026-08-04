import '../../domain/patcher/patch_args.dart';
import 'patch_object_descriptor.dart';

/// A typed creation-argument string checked against an object type's documented
/// [PatchParamDescriptor]s — the gate the inline object box runs before it will
/// instantiate anything (issue #358).
///
/// The engine takes creation parameters as one whitespace-separated string and
/// is unforgiving about them: a `.slider` registers no parameters at all and
/// *crashes* if handed any, and a value outside a documented range configures an
/// object nobody asked for. Typing an object name is a one-second gesture, so
/// the check has to happen before the object is minted, not after — hence a pure
/// value that both answers "is this typable?" ([problem]) and produces the exact
/// string to create with ([args]).
///
/// Two jobs, deliberately in one place, because they read the same metadata and
/// must agree:
/// - **Validate.** Too many arguments for the documented parameter list, a
///   non-numeric value where the documentation says a number, or a value outside
///   a documented `min..max` range each yield a short lowercase [problem] the
///   box shows inline while staying open for correction.
/// - **Resolve.** Fewer arguments than parameters is *fine*: the missing tail
///   falls back to each parameter's documented default, exactly as the params
///   dialog does when a field is cleared, so the arguments stay positional and
///   the *n*th value keeps meaning the *n*th parameter.
class PatchCreationArgs {
  const PatchCreationArgs._(this.args, this.problem);

  /// Check [typed] — the raw text after the object name — against [desc].
  factory PatchCreationArgs.check(PatchObjectDescriptor desc, String typed) {
    final given = splitPatchArgs(typed);
    final params = desc.params;
    if (given.length > params.length) {
      return PatchCreationArgs._('', _tooMany(desc, params.length));
    }
    for (var i = 0; i < given.length; i++) {
      final problem = _checkOne(params[i], given[i]);
      if (problem != null) return PatchCreationArgs._('', problem);
    }
    // Positional resolution: a documented default fills every slot the user did
    // not type, so `~sine` with no arguments still arrives configured.
    final resolved = [
      for (var i = 0; i < params.length; i++)
        i < given.length ? given[i] : params[i].defaultValue,
    ].join(' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    return PatchCreationArgs._(resolved, null);
  }

  /// The whitespace-joined creation-argument string to mint the object with.
  /// Empty when the type documents no parameters — which is what the objects
  /// that reject arguments outright need to be handed.
  final String args;

  /// Why the typed arguments were refused, or null when they are usable.
  final String? problem;

  bool get isValid => problem == null;

  static String _tooMany(PatchObjectDescriptor desc, int allowed) =>
      allowed == 0
      ? '${desc.type} takes no arguments'
      : '${desc.type} takes at most $allowed '
            '${allowed == 1 ? 'argument' : 'arguments'}';

  /// One documented parameter against one typed value.
  ///
  /// A parameter counts as numeric when its own documentation says so — a
  /// numeric default or a numeric range. Anything else (a name, a mode word) is
  /// passed through untouched: the engine's own metadata is the only authority
  /// here, and inventing a stricter rule than it documents would refuse
  /// arguments that are perfectly legal.
  static String? _checkOne(PatchParamDescriptor param, String value) {
    final range = _rangeOf(param.range);
    final numeric =
        range != null || double.tryParse(param.defaultValue) != null;
    if (!numeric) return null;
    final parsed = double.tryParse(value);
    if (parsed == null) return '${param.name} must be a number';
    if (range == null) return null;
    if (parsed < range.$1 || parsed > range.$2) {
      return '${param.name} must be in ${param.range}';
    }
    return null;
  }

  /// A documented `min..max` range as a numeric pair, or null when the range is
  /// absent or written as something else.
  static (double, double)? _rangeOf(String range) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*\.\.\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(range);
    if (match == null) return null;
    final lo = double.tryParse(match.group(1)!);
    final hi = double.tryParse(match.group(2)!);
    if (lo == null || hi == null) return null;
    return (lo, hi);
  }
}
