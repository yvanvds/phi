import 'package:flutter/widgets.dart';

import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_port_kind.dart';
import 'patcher_controller.dart';

/// How a node body widget is built. Lives in the [NodeDescriptor] so the
/// surface code is closed against new node types — adding `~lp` is one
/// new body file plus one registration call.
typedef NodeBodyBuilder =
    Widget Function(
      BuildContext context,
      PatchNode node,
      PatcherController controller,
    );

/// Spec for one port on a node type. Used at registration time; the live
/// port topology on a [PatchNode] is reified from the gateway's
/// [PatcherNodeSnapshot] (since the native side is authoritative).
class PortSpec {
  const PortSpec({required this.kind, this.label});
  final PatchPortKind kind;
  final String? label;
}

/// Static description of one node type.
///
/// One descriptor per `Obj.*` constant. Held by [NodeTypeRegistry] and
/// looked up at canvas-build time to render the node's body and pass the
/// right creation args to the gateway.
///
/// [buildBody] is what splits the two kinds of node the canvas draws (design
/// §7, issue #379): a descriptor **with** a body is a GUI object rendered in a
/// `PatchNodeFrame`, and one **without** — like every unregistered engine
/// object — is an object box, a single bordered line of its type and
/// arguments. [title] and [defaultSize] belong to the first kind only: an
/// object box renders no title and measures its own box from its text.
class NodeDescriptor {
  const NodeDescriptor({
    required this.type,
    required this.defaultArgs,
    required this.inputs,
    required this.outputs,
    this.title,
    this.defaultSize,
    this.buildBody,
    this.readsGuiValue = false,
  });

  /// One of the `Obj.*` string constants from `package:yse`.
  final String type;

  /// Display title for the node header. Uppercase mono. **Null for an object
  /// box**, which has no header to put it in — the type id is already the
  /// first thing its line says (issue #379). Kept for the GUI objects, whose
  /// headers only retire with issue #381.
  final String? title;

  /// On-canvas size. Null for an object box, which is measured from its line
  /// of text by `PatchObjectBoxMetrics` instead.
  final Size? defaultSize;

  /// Creation argument string passed to `Patcher.createObject`.
  final String defaultArgs;

  /// Declared port shapes — informational; ports are reified from the
  /// gateway's `inspect()` snapshot for source-of-truth.
  final List<PortSpec> inputs;
  final List<PortSpec> outputs;

  /// Builds the body widget shown below the node header — **null** for an
  /// object box, which is its own line of text and has no body slot.
  final NodeBodyBuilder? buildBody;

  /// Whether a node of this type renders as an object box rather than as a
  /// framed GUI control (design §7).
  bool get isObjectBox => buildBody == null;

  /// Whether the body **displays the engine's `guiValue`** — a fader readout, a
  /// number box, a toggle's on/off. Only these nodes are polled by the
  /// surface's gated refresh, so an idle patch of plain objects costs nothing
  /// (issue #357).
  ///
  /// Deliberately narrower than "the body is a live control": `.b` (a momentary
  /// bang) and `.m` (which renders its creation args) are operable but have no
  /// display value to re-read, so polling by "is it interactive" would burn
  /// reads on bodies that can never change from underneath. An **object box**
  /// never qualifies either — it prints the arguments the object was made
  /// with, which only a journaled `setParams` changes (issue #379).
  ///
  /// There is no companion "the body owns its presses" flag any more: since
  /// issue #378 that is the canvas's **mode**, not the type's — in edit mode
  /// every body is inert so the node can be dragged from anywhere on it, and in
  /// run mode every body is live.
  final bool readsGuiValue;
}

/// Global singleton mapping `Obj.*` strings to their [NodeDescriptor].
///
/// Populated once at app start via `registerBuiltInPatcherNodes()`.
/// Adding a new node type is a single `register(...)` call — the canvas
/// looks descriptors up by [PatchNode.type] and is closed against the set.
class NodeTypeRegistry {
  NodeTypeRegistry._();
  static final NodeTypeRegistry instance = NodeTypeRegistry._();

  final Map<String, NodeDescriptor> _byType = {};

  /// Register or overwrite the descriptor for [d.type].
  void register(NodeDescriptor d) {
    _byType[d.type] = d;
  }

  /// Look up a descriptor. Returns null if the type is unregistered.
  NodeDescriptor? find(String type) => _byType[type];

  /// All currently-registered descriptors.
  Iterable<NodeDescriptor> get all => _byType.values;

  /// Wipe the registry. Test-only.
  @visibleForTesting
  void clear() => _byType.clear();
}
