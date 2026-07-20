import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/tokens/phi_voices.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.b` (button / bang) node — a momentary trigger that fires a
/// bang into the object's hot inlet via [PatcherController.setControlBang]
/// (`sendBang`) on tap, flashing briefly in the node's voice colour (design
/// `docs/design/patcher.md` §7).
class ButtonNodeBody extends StatefulWidget {
  const ButtonNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<ButtonNodeBody> createState() => _ButtonNodeBodyState();
}

class _ButtonNodeBodyState extends State<ButtonNodeBody> {
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _bang() {
    widget.controller.setControlBang(widget.node.id, inlet: 0);
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final voice = PhiVoices.color(widget.node.voice);
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _bang,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _flash ? voice : PhiColors.bg2,
            borderRadius: PhiRadii.all2,
            border: Border.all(
              color: _flash ? voice : PhiColors.line2,
              width: 1.5,
            ),
            boxShadow: _flash
                ? [
                    BoxShadow(
                      color: PhiVoices.glow(widget.node.voice),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            'bang',
            style: PhiType.caption().copyWith(
              color: _flash ? PhiColors.bg0 : PhiColors.fg2,
            ),
          ),
        ),
      ),
    );
  }
}
