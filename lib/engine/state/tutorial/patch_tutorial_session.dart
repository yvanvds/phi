import 'dart:convert';

import '../../../domain/patcher/patch_object_types.dart';
import '../../../domain/patcher/tutorial/patch_tutorial.dart';
import '../../bridge/patcher_gateway.dart';
import '../patch_clipboard.dart';
import '../patcher_controller.dart';

/// One **open tutorial** (issue #489): a transient native patcher that is not
/// a registry entity.
///
/// It materialises the bundled [tutorial]'s dump as its own native patcher —
/// never touching the project, so opening, playing and closing it never
/// dirties or saves anything — binds a [PatcherController] editor to it so the
/// canvas renders it like any patch, and, when the patch makes sound (it holds
/// a `~dac`), mounts it on master while open. [dispose] unmounts and frees the
/// native patcher.
///
/// Read-only is the surface's job (it forces run mode and offers no edit
/// gesture); the session only owns the native lifetime.
class PatchTutorialSession {
  PatchTutorialSession._(
    this._gateway, {
    required this.tutorial,
    required this.slug,
    required this.instanceId,
    required this.editor,
    required this.mounted,
  });

  /// Materialise [tutorial] (stored under [slug]) as a fresh native patcher on
  /// [gateway], with an editor sharing [clipboard] so a fragment can be copied
  /// out of a tutorial into a project patch.
  factory PatchTutorialSession.open(
    PatcherGateway gateway, {
    required PatchTutorial tutorial,
    required String slug,
    PatchClipboard? clipboard,
  }) {
    // Anonymous on purpose: a tutorial must not register on the engine-direct
    // bus under a name a project patch could also be using.
    final instanceId = gateway.createInstance(mainOutputs: 1);
    gateway.parseJson(instanceId, jsonEncode(tutorial.payload.dump));
    final editor = PatcherController.bound(
      gateway,
      instanceId: instanceId,
      clipboard: clipboard,
    )..rebuildFromInstance();
    // Mounting reads `~dac` on every audio callback, so only a patch that has
    // one is mounted (a control-only tutorial stays silent and unmounted).
    final audible = editor.graph.nodes.any(
      (n) => n.type == PatchObjectTypes.dDac,
    );
    if (audible) gateway.mountAsSource(instanceId);
    return PatchTutorialSession._(
      gateway,
      tutorial: tutorial,
      slug: slug,
      instanceId: instanceId,
      editor: editor,
      mounted: audible,
    );
  }

  final PatcherGateway _gateway;

  /// The tutorial being shown.
  final PatchTutorial tutorial;

  /// The slug it is stored under (`metro`, `sig-plus`).
  final String slug;

  /// The transient native patcher.
  final int instanceId;

  /// The editor the canvas binds to while the tutorial is open.
  final PatcherController editor;

  /// Whether the patcher is mounted on master (it holds a `~dac`).
  final bool mounted;

  bool _disposed = false;

  /// Unmount, drop the editor and free the native patcher. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (mounted) _gateway.unmountSource(instanceId);
    editor.dispose();
    _gateway.disposeInstance(instanceId);
  }
}
