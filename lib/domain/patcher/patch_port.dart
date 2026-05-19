import 'patch_port_kind.dart';

/// One inlet or outlet on a [PatchNode].
///
/// Immutable — port topology is fixed once a node is created, since the
/// native patcher object's inlet/outlet count is decided at construction.
/// To reshape, delete and recreate the node.
enum PatchPortSide { input, output }

class PatchPort {
  const PatchPort({
    required this.index,
    required this.side,
    required this.kind,
    required this.voice,
    this.label,
  });

  /// 0-based index among ports on the same [side].
  final int index;

  final PatchPortSide side;
  final PatchPortKind kind;

  /// Voice swatch (1..6) — same value as the owning node's voice for now.
  /// Carried per-port so the cable layer can colour each cable end-to-end.
  final int voice;

  /// Optional display label (e.g. `freq`, `cutoff`). Body rows can ignore.
  final String? label;
}
