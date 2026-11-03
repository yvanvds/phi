import 'package:material_ui/material_ui.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';
import '../../../engine/state/patcher_controller.dart';
import '../patch_canvas_mode.dart';
import '../patcher_canvas.dart';

/// What one subpatch window shows (issue #481): a slim bar naming the
/// subpatch's path and the canvas mode, over a full [PatcherCanvas] scoped to
/// the box's contents.
///
/// The canvas drives the patch's own [PatcherController], so creating,
/// wiring, moving, deleting and undoing here are the same journaled verbs the
/// main window uses, on the same graph. The mode is the surface's: one patch
/// is played or edited as a whole, wherever it is shown.
///
/// The window is its own view, so it brings what a popup needs with it: a
/// [Navigator] (and so an [Overlay]) for the node menu and the tooltips, which
/// would otherwise open in the main window, where the inherited ones live.
class SubpatchWindowView extends StatelessWidget {
  const SubpatchWindowView({
    required this.editor,
    required this.box,
    required this.objectTypes,
    this.root,
    this.mode = PatchCanvasMode.edit,
    this.snapToGrid = false,
    this.onToggleMode,
    this.onCreateObject,
    this.onNodeTap,
    this.onNodeContextMenu,
    this.onOpenSubpatch,
    this.onTypeResolved,
    super.key,
  });

  /// The editor of the patch the subpatch belongs to.
  final PatcherController editor;

  /// The subpatch box this window shows the inside of, or null for the whole of
  /// [editor]'s patch: the definition of an abstraction (issue #553).
  final PatchNodeId? box;

  /// What the window's path starts with when it is not the main window's patch.
  final String? root;

  /// The engine catalogue, for the inline object box.
  final List<PatchObjectDescriptor> objectTypes;

  /// The surface's canvas mode (issue #378).
  final PatchCanvasMode mode;

  /// Whether a node drop lands on the grid (issue #368).
  final bool snapToGrid;

  /// Flips the mode; null hides the toggle (a read-only tutorial).
  final VoidCallback? onToggleMode;

  /// Creates an object inside [box]; null makes the window read-only.
  final void Function(
    PatchObjectDescriptor desc,
    Offset canvasPosition, {
    String? args,
  })?
  onCreateObject;

  /// A node was tapped — the main window's reference panel follows.
  final void Function(PatchNode node)? onNodeTap;

  /// A right-click on a node, with a [BuildContext] inside this window, so the
  /// menu opens here.
  final void Function(BuildContext context, PatchNode node, Offset global)?
  onNodeContextMenu;

  /// Open a subpatch nested inside this one.
  final void Function(PatchNode box)? onOpenSubpatch;

  /// The inline box settled on a type.
  final void Function(PatchObjectDescriptor desc)? onTypeResolved;

  /// Key on the bar's path title.
  static const Key titleKey = Key('SubpatchWindowView.title');

  /// Key on the bar's edit / run toggle.
  static const Key modeKey = Key('SubpatchWindowView.mode');

  /// Key on the scoped canvas.
  static const Key canvasKey = Key('SubpatchWindowView.canvas');

  @override
  Widget build(BuildContext context) {
    return _WindowConfig(
      view: this,
      // A Navigator of the window's own; the app's HeroController belongs to
      // the main window's Navigator and may not be shared.
      child: HeroControllerScope.none(
        child: Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const _WindowBody(),
          ),
        ),
      ),
    );
  }
}

/// Hands the window's configuration to the page inside its [Navigator]: a
/// route's page is built once, but a dependency on an inherited widget above
/// it still rebuilds it — so a mode flip in the main window reaches here.
class _WindowConfig extends InheritedWidget {
  const _WindowConfig({required this.view, required super.child});

  final SubpatchWindowView view;

  static SubpatchWindowView of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WindowConfig>()!.view;

  @override
  bool updateShouldNotify(_WindowConfig oldWidget) =>
      !identical(view, oldWidget.view);
}

class _WindowBody extends StatelessWidget {
  const _WindowBody();

  @override
  Widget build(BuildContext context) {
    final view = _WindowConfig.of(context);
    final menu = view.onNodeContextMenu;
    return Material(
      color: PhiColors.bg0,
      // A native window's first frame comes before the platform has sized it
      // (1x1 on Linux, #557): show nothing until the bar fits.
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < _WindowBar.height) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WindowBar(view: view),
              Expanded(
                child: PatcherCanvas(
                  key: SubpatchWindowView.canvasKey,
                  controller: view.editor,
                  scope: view.box,
                  objectTypes: view.onCreateObject == null
                      ? const []
                      : view.objectTypes,
                  snapToGrid: view.snapToGrid,
                  mode: view.mode,
                  onToggleMode: view.onToggleMode,
                  onCreateObject: view.onCreateObject,
                  onNodeTap: view.onNodeTap,
                  onNodeContextMenu: menu == null
                      ? null
                      : (node, global) => menu(context, node, global),
                  onOpenSubpatch: view.onOpenSubpatch,
                  onTypeResolved: view.onTypeResolved,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The window's bar: the subpatch's path, and the mode it is being edited or
/// played in.
class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.view});

  static const double height = 32;

  final SubpatchWindowView view;

  @override
  Widget build(BuildContext context) {
    final run = view.mode.isRun;
    final fg = run ? PhiColors.live : PhiColors.fg1;
    final toggle = view.onToggleMode;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              // The path follows a rename of this box or of one around it.
              listenable: view.editor.graph,
              builder: (context, _) => Text(
                view.editor.scopeTitle(view.box, root: view.root),
                key: SubpatchWindowView.titleKey,
                overflow: TextOverflow.ellipsis,
                style: PhiType.monoS().copyWith(color: PhiColors.fg0),
              ),
            ),
          ),
          if (toggle != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: SubpatchWindowView.modeKey,
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PhiSpacing.s1,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: fg.withValues(alpha: 0.5)),
                    borderRadius: PhiRadii.all1,
                  ),
                  child: Text(
                    view.mode.label.toUpperCase(),
                    style: PhiType.caption().copyWith(color: fg),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
