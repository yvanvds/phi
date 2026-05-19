import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/midi_transform_chain.dart';
import 'midi_header_strip.dart';
import 'piano_roll_view.dart';
import 'transform_chain_panel.dart';

/// Stateful host for the [MidiTransformChain]. Subscribes via
/// [ListenableBuilder] so toggling a chip updates both the chain panel and
/// the piano roll without manual setState calls.
class MidiViewport extends StatefulWidget {
  const MidiViewport({required this.chain, super.key});

  final MidiTransformChain chain;

  @override
  State<MidiViewport> createState() => _MidiViewportState();
}

class _MidiViewportState extends State<MidiViewport> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.chain,
      builder: (context, _) {
        final clip = widget.chain.source;
        final output = widget.chain.output;
        return Container(
          color: PhiColors.bg0,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MidiHeaderStrip(
                clipName: clip.name,
                noteCount: output.length,
                bars: clip.bars,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: PianoRollView(
                        notes: output,
                        bars: clip.bars,
                        beatsPerBar: clip.beatsPerBar,
                        version: widget.chain.version,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 250,
                      child: TransformChainPanel(chain: widget.chain),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
