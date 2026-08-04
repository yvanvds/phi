import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `~sine` node — a `freq <value>` readout of the oscillator's
/// **real** frequency (issue #354; it used to print a hardcoded `440`).
///
/// The value is read on every build, never cached. The engine's live display
/// value ([PatcherController.guiValueOf]) wins whenever the object reports one —
/// that is what a cable or a `sendFloat` into the freq inlet leaves behind —
/// and otherwise the readout falls back to the node's creation argument
/// ([PatcherController.argsOf]), the frequency the object was made with and what
/// the params dialog edits. An object with neither shows a dim placeholder
/// rather than inventing a number.
///
/// A params apply and its undo/redo both run through
/// [PatcherController.setNodeParams], which wakes the node, so the readout
/// follows the dialog immediately. A *cable-driven* change still needs
/// something to repaint the node; the polling refresh that makes those land on
/// their own is issue #357.
class SineNodeBody extends StatelessWidget {
  const SineNodeBody({required this.node, required this.controller, super.key});

  final PatchNode node;
  final PatcherController controller;

  /// Shown when the object reports neither a live value nor creation args —
  /// better an honest blank than an invented number, which is the whole point
  /// of issue #354.
  static const String _unknownValue = '—';

  @override
  Widget build(BuildContext context) {
    final freq = _frequency();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('freq', style: PhiType.monoS().copyWith(color: PhiColors.fg2)),
        Text(
          freq.isEmpty ? _unknownValue : freq,
          style: PhiType.monoS().copyWith(
            color: freq.isEmpty ? PhiColors.fg3 : PhiColors.fg0,
          ),
        ),
      ],
    );
  }

  /// The frequency to display: the engine's `guiValue` when it reports one,
  /// else the first creation argument. Empty when neither is known.
  String _frequency() {
    final gui = controller.guiValueOf(node.id).trim();
    if (gui.isNotEmpty) return _format(gui);
    final args = controller.argsOf(node.id).trim();
    if (args.isEmpty) return '';
    return _format(args.split(RegExp(r'\s+')).first);
  }

  /// Numbers render the way the number bodies render them — a whole value with
  /// no trailing `.0`. Anything unparseable passes through untouched, so a
  /// symbolic argument still shows what the object was actually given.
  static String _format(String raw) {
    final d = double.tryParse(raw);
    if (d == null) return raw;
    return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
  }
}
