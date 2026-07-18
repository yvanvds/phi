/// The sections of the settings dialog (design
/// `docs/design/settings-and-devices.md` §6) — the left-hand list the performer
/// picks between.
///
/// Only [audio] carries fields today (issue #154); [midi], [projects], and
/// [diagnostics] are placeholders until the follow-up issue fills them in, but
/// they list here so the shell shows the whole surface from the start.
enum SettingsSection {
  audio('AUDIO'),
  midi('MIDI'),
  projects('PROJECTS'),
  diagnostics('DIAGNOSTICS');

  const SettingsSection(this.label);

  /// The upper-case label shown in the section list.
  final String label;
}
