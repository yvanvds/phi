import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_transform_chain.dart';
import 'midi_header_strip.dart';
import 'piano_roll_editor.dart';
import 'transform_chain_panel.dart';
import 'velocity_lane.dart';

/// Stateful host for the [MidiTransformChain] and its [ClipEditor]. Listens to
/// both (merged) so toggling a chip *or* editing a note repaints the roll, the
/// velocity lane and the chain panel without manual setState calls.
///
/// The editor is injected by the shell so its undo history and selection
/// survive surface switches; when none is supplied (widget tests) the viewport
/// owns one built from the chain's source clip.
class MidiViewport extends StatefulWidget {
  const MidiViewport({required this.chain, this.editor, super.key});

  final MidiTransformChain chain;
  final ClipEditor? editor;

  @override
  State<MidiViewport> createState() => _MidiViewportState();
}

class _MidiViewportState extends State<MidiViewport> {
  late final ClipEditor _editor;
  late final bool _ownsEditor;
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();
    _ownsEditor = widget.editor == null;
    _editor = widget.editor ?? ClipEditor(widget.chain.source);
    _listenable = Listenable.merge([widget.chain, _editor]);
  }

  @override
  void dispose() {
    if (_ownsEditor) _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final clip = widget.chain.source;
        final showGhost = widget.chain.transforms.any((t) => t.active);
        return Container(
          color: PhiColors.bg0,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MidiHeaderStrip(
                clipName: clip.name,
                noteCount: clip.notes.length,
                bars: clip.bars,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: PianoRollEditor(
                              editor: _editor,
                              ghostNotes: widget.chain.output,
                              showGhost: showGhost,
                              bars: clip.bars,
                              beatsPerBar: clip.beatsPerBar,
                            ),
                          ),
                          const SizedBox(height: 8),
                          VelocityLane(
                            editor: _editor,
                            notes: clip.notes,
                            bars: clip.bars,
                            beatsPerBar: clip.beatsPerBar,
                          ),
                        ],
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
