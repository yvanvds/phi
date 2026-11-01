import 'dart:convert';

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
/// canvas renders it like any patch, and mounts it on master while open.
/// [dispose] unmounts and frees the native patcher.
///
/// **Every tutorial is mounted (issue #528)**, not only one with a `~dac`: on
/// libYSE 3.1.0 several control objects run on the audio clock and advance
/// only in a mounted, rendered patcher — `.line` ramps, `.delay`, `.pipe`,
/// `.thresh`, `.quickthresh`, `.qlim` and `.makenote`'s note-off. (`.metro`,
/// `.clocker` and `.timer` run on wall-clock time.) A mounted patch without a
/// `~dac` is silent, and only one tutorial is open at a time.
///
/// The tutorial is its own session: mounting it never mounts, starts or
/// places the user's own patch (#523).
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
    // Always mounted: audio-clocked control objects (`.line`, `.delay`, …)
    // only run in a mounted, rendered patcher (#528). Without a `~dac` it is
    // silent.
    gateway.mountAsSource(instanceId);
    return PatchTutorialSession._(
      gateway,
      tutorial: tutorial,
      slug: slug,
      instanceId: instanceId,
      editor: editor,
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

  bool _disposed = false;

  /// Unmount, drop the editor and free the native patcher. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _gateway.unmountSource(instanceId);
    editor.dispose();
    _gateway.disposeInstance(instanceId);
  }
}
