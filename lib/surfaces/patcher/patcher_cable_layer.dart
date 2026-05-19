import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_cable_painter.dart';
import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_port_id.dart';

/// Thin wrapper that hands the cable list + port-position map to
/// [PatchCablePainter]. Repaints only when the supplied [version] changes.
class PatcherCableLayer extends StatelessWidget {
  const PatcherCableLayer({
    required this.cables,
    required this.portPositions,
    required this.cableVoiceForSource,
    required this.version,
    super.key,
  });

  final List<PatchCable> cables;
  final Map<PatchPortId, Offset> portPositions;
  final Map<PatchPortId, int> cableVoiceForSource;
  final int version;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: PatchCablePainter(
          cables: cables,
          portPositions: portPositions,
          cableVoiceForSource: cableVoiceForSource,
          version: version,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
