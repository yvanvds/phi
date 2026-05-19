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
class NodeDescriptor {
  const NodeDescriptor({
    required this.type,
    required this.title,
    required this.defaultSize,
    required this.defaultArgs,
    required this.inputs,
    required this.outputs,
    required this.buildBody,
  });

  /// One of the `Obj.*` string constants from `package:yse`.
  final String type;

  /// Display title for the node header. Uppercase mono.
  final String title;

  /// On-canvas size.
  final Size defaultSize;

  /// Creation argument string passed to `Patcher.createObject`.
  final String defaultArgs;

  /// Declared port shapes — informational; ports are reified from the
  /// gateway's `inspect()` snapshot for source-of-truth.
  final List<PortSpec> inputs;
  final List<PortSpec> outputs;

  /// Builds the body widget shown below the node header.
  final NodeBodyBuilder buildBody;
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
