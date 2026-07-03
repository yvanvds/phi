import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';

/// The `(name, expected)` pair a [RuntimeVariableCondition] needs.
class RuntimeVariableInput {
  const RuntimeVariableInput({required this.name, required this.expected});

  final String name;

  /// The value the variable must equal. Kept as a string — the performance
  /// exposes runtime variables as opaque values and there is no registry to
  /// type them against yet (a follow-up), so the picker compares as text.
  final String expected;
}

/// Modal that authors a runtime-variable guard: a variable name and the value
/// it must equal. Owns its controllers so their exit animation never outlives
/// them (the same "used after disposed" trap the chain rename dialog avoids).
///
/// There is no domain registry of runtime variables yet, so both fields are
/// free text — the value the performance later writes into
/// `GraphEvalContext.variables[name]` must `== expected` for the edge to open.
class RuntimeVariableDialog extends StatefulWidget {
  const RuntimeVariableDialog({
    this.initialName = '',
    this.initialExpected = '',
    super.key,
  });

  final String initialName;
  final String initialExpected;

  @override
  State<RuntimeVariableDialog> createState() => _RuntimeVariableDialogState();
}

class _RuntimeVariableDialogState extends State<RuntimeVariableDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _expected = TextEditingController(
    text: widget.initialExpected,
  );

  @override
  void dispose() {
    _name.dispose();
    _expected.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pop(RuntimeVariableInput(name: name, expected: _expected.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'runtime variable',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            decoration: const InputDecoration(
              hintText: 'name (e.g. intensity)',
            ),
          ),
          TextField(
            controller: _expected,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            decoration: const InputDecoration(hintText: 'equals (e.g. high)'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('set')),
      ],
    );
  }
}
