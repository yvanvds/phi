import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_args.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/bridge/patch_object_descriptor.dart';
import '../../../engine/state/patcher_controller.dart';

/// Opens the metadata-driven params dialog for [node] — one field per
/// documented creation parameter, applied via `setParams` on confirm.
Future<void> showPatchParamsDialog(
  BuildContext context, {
  required PatcherController controller,
  required PatchNode node,
  required PatchObjectDescriptor descriptor,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PatchParamsDialog(
      controller: controller,
      node: node,
      descriptor: descriptor,
    ),
  );
}

/// Modal editing a non-GUI node's documented creation parameters (design
/// `docs/design/patcher.md` §7) — the same metadata-driven-editor pattern as
/// the MIDI transform editors, but sourced from the gateway's engine metadata.
///
/// One text field per [PatchParamDescriptor] in the object's declared order,
/// seeded from the node's current argument string (falling back to each
/// parameter's documented default). Confirming joins the fields back into one
/// whitespace-separated argument string and applies it through
/// [PatcherController.applyParams] — a single journaled `setParams`, so the
/// whole edit round-trips under one Ctrl+Z.
class PatchParamsDialog extends StatefulWidget {
  const PatchParamsDialog({
    required this.controller,
    required this.node,
    required this.descriptor,
    super.key,
  });

  final PatcherController controller;
  final PatchNode node;
  final PatchObjectDescriptor descriptor;

  /// Key on the confirm button.
  static const Key doneKey = Key('PatchParamsDialog.done');

  /// Key on one parameter's text field.
  static Key fieldKey(String name) => Key('PatchParamsDialog.field.$name');

  @override
  State<PatchParamsDialog> createState() => _PatchParamsDialogState();
}

class _PatchParamsDialogState extends State<PatchParamsDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final parts = splitPatchArgs(widget.controller.argsOf(widget.node.id));
    _controllers = [
      for (var i = 0; i < widget.descriptor.params.length; i++)
        TextEditingController(
          text: i < parts.length
              ? parts[i]
              : widget.descriptor.params[i].defaultValue,
        ),
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final params = widget.descriptor.params;
    // Keep the arguments positional: a cleared field falls back to its
    // documented default so later parameters stay aligned to their slot.
    final values = [
      for (var i = 0; i < params.length; i++)
        _controllers[i].text.trim().isEmpty
            ? params[i].defaultValue
            : _controllers[i].text.trim(),
    ];
    widget.controller.applyParams(widget.node.id, values.join(' ').trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final params = widget.descriptor.params;
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit parameters · ${widget.descriptor.type}',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (params.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s2),
                child: Text(
                  'this object has no editable parameters',
                  style: PhiType.small().copyWith(color: PhiColors.fg2),
                ),
              )
            else
              for (var i = 0; i < params.length; i++)
                _ParamRow(param: params[i], controller: _controllers[i]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(
          key: PatchParamsDialog.doneKey,
          onPressed: _apply,
          child: const Text('apply'),
        ),
      ],
    );
  }
}

/// One documented parameter: its name + value field, with a dim doc/range line.
class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.param, required this.controller});

  final PatchParamDescriptor param;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (param.defaultValue.isNotEmpty) 'default ${param.defaultValue}',
      if (param.range.isNotEmpty) 'range ${param.range}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  param.name,
                  style: PhiType.monoS().copyWith(color: PhiColors.fg1),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  key: PatchParamsDialog.fieldKey(param.name),
                  controller: controller,
                  style: PhiType.monoS().copyWith(color: PhiColors.fg0),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ],
          ),
          if (param.doc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: PhiSpacing.s0),
              child: Text(
                param.doc,
                style: PhiType.small().copyWith(color: PhiColors.fg2),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: PhiSpacing.s0),
              child: Text(
                meta.join('  ·  '),
                style: PhiType.caption().copyWith(color: PhiColors.fg3),
              ),
            ),
        ],
      ),
    );
  }
}
