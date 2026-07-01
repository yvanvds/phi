import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_clip.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/smf/smf_exception.dart';
import '../../domain/midi/smf/smf_reader.dart';
import '../../domain/midi/smf/smf_writer.dart';
import 'file_selector_midi_file_io.dart';
import 'midi_file_io.dart';
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
///
/// SMF import/export (issue #30) is wired here: the whole surface is a drop
/// target for `.mid` files, and the header carries import/export buttons.
/// Importing rewrites the shared source clip in place (so the chain, editor
/// and engine player keep their references) and resets the editor history;
/// exporting encodes the chain's transformed [MidiTransformChain.output].
class MidiViewport extends StatefulWidget {
  const MidiViewport({
    required this.chain,
    this.editor,
    this.playhead,
    this.fileIo,
    super.key,
  });

  final MidiTransformChain chain;
  final ClipEditor? editor;

  /// The engine player's beat position (issue #29). `null` in setups without
  /// a wired MIDI player; the editor then parks the playhead at the origin.
  final ValueListenable<double>? playhead;

  /// File-dialog backend for the import/export buttons. Defaults to the real
  /// `file_selector`-backed implementation; tests inject a fake.
  final MidiFileIo? fileIo;

  @override
  State<MidiViewport> createState() => _MidiViewportState();
}

class _MidiViewportState extends State<MidiViewport> {
  late final ClipEditor _editor;
  late final bool _ownsEditor;
  late final Listenable _listenable;
  late final MidiFileIo _fileIo;

  static const _reader = SmfReader();
  static const _writer = SmfWriter();

  /// Transient import error surfaced in the header; cleared on the next
  /// successful import or when a new one is attempted.
  String? _importError;

  @override
  void initState() {
    super.initState();
    _ownsEditor = widget.editor == null;
    _editor = widget.editor ?? ClipEditor(widget.chain.source);
    _listenable = Listenable.merge([widget.chain, _editor]);
    _fileIo = widget.fileIo ?? const FileSelectorMidiFileIo();
  }

  @override
  void dispose() {
    if (_ownsEditor) _editor.dispose();
    super.dispose();
  }

  // ── Import / export ────────────────────────────────────────────────────────

  Future<void> _pickAndImport() async {
    final bytes = await _fileIo.openSmf();
    if (bytes != null) _importBytes(bytes);
  }

  /// Parse [bytes] as SMF and swap them into the shared source clip. The
  /// chain, editor and engine player all hold the *same* clip reference, so a
  /// mutate-in-place keeps every wiring point intact; the editor history is
  /// reset because its note indices no longer line up.
  void _importBytes(Uint8List bytes) {
    try {
      final imported = _reader.read(bytes);
      widget.chain.source.replaceWith(imported);
      _editor.reset();
      widget.chain.notifySourceChanged();
      if (mounted) setState(() => _importError = null);
    } on SmfFormatException catch (e) {
      if (mounted) {
        setState(() => _importError = 'import failed · ${e.message}');
      }
    }
  }

  Future<void> _export() async {
    final source = widget.chain.source;
    // Export the transformed output, not the raw source — per the vision the
    // clip is "interpreted, not played", and the file should carry what the
    // chain currently yields.
    final rendered = MidiClip(
      name: source.name,
      notes: widget.chain.output,
      bars: source.bars,
      beatsPerBar: source.beatsPerBar,
    );
    await _fileIo.saveSmf('${source.name}.mid', _writer.write(rendered));
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    // Import the first dropped file that looks like a MIDI file; ignore the
    // rest (Phi has one clip per surface).
    for (final file in details.files) {
      if (_isMidiName(file.name)) {
        _importBytes(await file.readAsBytes());
        return;
      }
    }
  }

  static bool _isMidiName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mid') || lower.endsWith('.midi');
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: _onDrop,
      child: ListenableBuilder(
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
                  onImport: _pickAndImport,
                  onExport: _export,
                  errorText: _importError,
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
                                playhead: widget.playhead,
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
      ),
    );
  }
}
