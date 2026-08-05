/// The engine's `~` (DSP) / `.` (control) type-id prefix, read rather than
/// drawn (design §5, §12.4, issue #380).
///
/// Every engine object is registered under a prefixed id — `~sine`, `.metro`,
/// `~*`. That prefix is doing one job, telling you which domain the object
/// belongs to, and colour already does that job everywhere else in Phi: the
/// cables are typed by colour and the overview uses the same blue. So the id
/// stays **canonical** — it is what you type, complete on, search for, save and
/// hand to the gateway — and what gets *rendered* is [bare], coloured by
/// [isDsp].
///
/// Pure Dart on purpose: the same two facts are needed by the canvas box, the
/// palette, the completion list and the reference panel, and a rule about a
/// string should not have to be restated in each of them.
abstract final class PatchTypeName {
  /// [type] without its `~`/`.` prefix — `~sine` → `sine`, `.+` → `+`.
  ///
  /// A bare id (the engine's `patcher`) and the prefix on its own come back
  /// untouched: stripping the last character would leave nothing to read.
  static String bare(String type) {
    if (type.length < 2) return type;
    final first = type[0];
    return first == '~' || first == '.' ? type.substring(1) : type;
  }

  /// Whether [type] names a DSP / audio-rate object — the `~` convention the
  /// engine's own object list is built on.
  static bool isDsp(String type) => type.startsWith('~');
}
