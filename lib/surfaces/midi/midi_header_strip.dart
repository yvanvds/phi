import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/capsule/capsule.dart';

/// Top header above the piano roll: clip name, note count + meter caption,
/// and the two context capsules ("D dorian", "domain · drum") from the
/// mockup. Capsules are static for the scaffold — wiring them to the live
/// scale/time-domain state is a follow-up.
class MidiHeaderStrip extends StatelessWidget {
  const MidiHeaderStrip({
    required this.clipName,
    required this.noteCount,
    required this.bars,
    super.key,
  });

  final String clipName;
  final int noteCount;
  final int bars;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('midi · $clipName'.toUpperCase(), style: PhiType.caption()),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '$noteCount notes · $bars bars · interpreted, not played',
            style: PhiType.monoS().copyWith(color: PhiColors.fg3),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
        const Capsule(label: 'D dorian'),
        const SizedBox(width: 8),
        const Capsule(label: 'domain · drum', color: PhiColors.cool),
      ],
    );
  }
}
