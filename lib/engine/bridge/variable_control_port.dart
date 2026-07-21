/// The runtime-variable store as the live-coding **control plane** sees it — the
/// receiving end of `phi.ctl.var.*` assignments (design
/// `docs/design/live-coding.md` §4, issue #233).
///
/// `var.section = "b"` in a script publishes `phi.ctl.var.section` carrying the
/// assigned value; the [ControlPlaneDispatcher] decodes it and calls [set]. The
/// value keeps its bus type across the boundary, so [value] is a plain Dart
/// `String`, `int`, `double`, or `List<double>` — never a bus wrapper. The
/// owning controller (the runtime-variable registry) decides how to store or
/// coerce it.
///
/// A port so the dispatcher is testable against a fake; the real wiring adapts
/// the live `RuntimeVariableRegistry`.
abstract interface class VariableControlPort {
  /// Set the runtime variable named [name] to [value] (the decoded bus value:
  /// `String` / `int` / `double` / `List<double>`).
  void set(String name, Object? value);
}
