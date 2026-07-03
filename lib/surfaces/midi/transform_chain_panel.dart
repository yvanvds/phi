import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../domain/midi/custom_transform_definition.dart';
import '../../domain/midi/custom_transform_registry.dart';
import '../../domain/midi/midi_transform_chain.dart';
import 'transform_chip.dart';

/// 250px right-hand sidebar listing the [MidiTransformChain]'s transforms.
/// Chip taps flip `active` on the chain at that index. The header `+` opens a
/// menu of performer-authored transforms from the [registry] (issue #38);
/// picking one appends it to the chain. With no [registry] wired the `+` stays
/// inert (plain widget-test setups).
class TransformChainPanel extends StatefulWidget {
  const TransformChainPanel({required this.chain, this.registry, super.key});

  final MidiTransformChain chain;
  final CustomTransformRegistry? registry;

  @override
  State<TransformChainPanel> createState() => _TransformChainPanelState();
}

class _TransformChainPanelState extends State<TransformChainPanel> {
  bool _menuOpen = false;

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _add(CustomTransformDefinition definition) {
    widget.chain.add(definition.instantiate());
    setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final transforms = widget.chain.transforms;
    final registry = widget.registry;
    return Container(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            canAdd: registry != null,
            menuOpen: _menuOpen,
            onAddTap: _toggleMenu,
          ),
          if (_menuOpen && registry != null)
            _AddMenu(registry: registry, onPick: _add),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (var i = 0; i < transforms.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TransformChip(
                      transform: transforms[i],
                      onToggle: () =>
                          widget.chain.setActiveAt(i, !transforms[i].active),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canAdd,
    required this.menuOpen,
    required this.onAddTap,
  });

  final bool canAdd;
  final bool menuOpen;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Text(
            'transform chain'.toUpperCase(),
            style: PhiType.caption().copyWith(color: PhiColors.fg1),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canAdd ? onAddTap : null,
            child: Text(
              menuOpen ? '×' : '+',
              style: PhiType.monoS().copyWith(
                color: canAdd ? PhiColors.fg1 : PhiColors.fg3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dropdown of the [registry]'s custom transforms, shown under the header when
/// the `+` is open. Rebuilds with its host (the viewport merges the registry
/// into its listenable), so a hot-registered transform appears live.
class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.registry, required this.onPick});

  final CustomTransformRegistry registry;
  final ValueChanged<CustomTransformDefinition> onPick;

  @override
  Widget build(BuildContext context) {
    final definitions = registry.definitions;
    return Container(
      decoration: const BoxDecoration(
        color: PhiColors.bg2,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (definitions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: _EmptyHint(),
            )
          else
            for (final def in definitions)
              _MenuRow(definition: def, onTap: () => onPick(def)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.definition, required this.onTap});

  final CustomTransformDefinition definition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(definition.kind.voiceIndex);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                definition.kind.tag.toUpperCase(),
                style: PhiType.monoS().copyWith(
                  fontSize: 8,
                  color: color,
                  letterSpacing: 0.08 * 8,
                ),
              ),
            ),
            Expanded(
              child: Text(
                definition.name,
                style: PhiType.monoS().copyWith(
                  fontSize: 11,
                  color: PhiColors.fg0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'no custom transforms — define one from the Code surface',
      style: PhiType.monoS().copyWith(fontSize: 10, color: PhiColors.fg3),
    );
  }
}
