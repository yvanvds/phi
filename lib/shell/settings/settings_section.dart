/// The sections of the settings dialog (design
/// `docs/design/settings-and-devices.md` §6) — the left-hand list the performer
/// picks between.
///
/// All four carry fields: [audio] (issue #154), and [midi], [projects], and
/// [diagnostics] (issue #151).
enum SettingsSection {
  audio('AUDIO'),
  midi('MIDI'),
  projects('PROJECTS'),
  diagnostics('DIAGNOSTICS');

  const SettingsSection(this.label);

  /// The upper-case label shown in the section list.
  final String label;
}
