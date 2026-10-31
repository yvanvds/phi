/// Which read form of the engine's GUI value protocol a node body polls
/// (issue #469).
///
/// The engine's rule is **one read form per object per frame**: either the
/// coherent whole-state string (`guiValue`) or the per-cell reads
/// (`guiValueCount` + `guiValueAt`), never both — some reads are destructive,
/// and per-cell reads are not atomic across cells. A body declares its form on
/// `NodeDescriptor.guiValueRead`, and `PatcherController.refreshGuiValues`
/// polls that form and no other.
enum GuiValueRead {
  /// Poll the whole state as one string — the scalar controls (`.slider`,
  /// `.i`, `.t`, `.dial`, ...) and any body that wants a coherent snapshot.
  whole,

  /// Poll the cell count and then each cell in the body's window
  /// (`PatcherController.setGuiCellWindow`, all cells by default) — the large
  /// controls (`.multislider`, `.kslider`, `.matrixctrl`) that repaint only
  /// the cells they show.
  cells,
}
