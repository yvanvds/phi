/// Phi's application version, surfaced in the diagnostics bundle (design
/// `docs/design/diagnostics.md` §6, issue #272).
///
/// Kept as a plain constant rather than read through `package_info_plus`: Phi is
/// a single-user local instrument, so an extra platform plugin (and its async
/// init + test mocking) buys nothing over one line to keep in step with
/// `pubspec.yaml`'s `version:` field. Update both together on a release bump.
const String phiAppVersion = '0.1.0';
