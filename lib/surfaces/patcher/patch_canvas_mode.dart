/// Whether the patcher canvas is being **edited** or **played** (design
/// `docs/design/patcher.md` §6 and §12.5, issue #378).
///
/// The mode exists because the object-box epic (#375) takes the header away:
/// with no neutral chrome left on a GUI node, per-node arbitration ("a live
/// body owns its own presses") leaves a fader unmovable and un-marquee-able.
/// A mode resolves that globally — and a live-performance surface wants the
/// split on its own terms, as a state where the patch is *played* and nothing
/// can be nudged out of place by accident.
///
/// It is **performance state**: held per open surface, never written to the
/// payload, so a reopened project starts in [edit].
enum PatchCanvasMode {
  /// Bodies are inert — a fader does not move, a number box does not take
  /// focus. A press anywhere on a node drags it, a marquee sweeps across GUI
  /// nodes like any others, and `Delete`, `Ctrl+D` and the arrow nudges live.
  edit,

  /// Bodies are live and own every press. Nodes neither move nor select nor
  /// delete; only navigation — pan, zoom, `Ctrl+0` — still answers, because
  /// navigating is not editing.
  run;

  bool get isEdit => this == PatchCanvasMode.edit;
  bool get isRun => this == PatchCanvasMode.run;

  /// The other mode — what `Ctrl+E` and the placement bar's toggle ask for.
  PatchCanvasMode get flipped => isEdit ? run : edit;

  /// Short uppercase label for the placement bar's indicator.
  String get label => isEdit ? 'edit' : 'run';
}
