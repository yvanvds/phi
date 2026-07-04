import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';

/// The `(name, values)` a runtime variable is defined by: its name and the
/// enumerated candidate values it can take.
class RuntimeVariableDefinition {
  const RuntimeVariableDefinition({required this.name, required this.values});

  final String name;

  /// The candidate values, in author order. Non-empty when the dialog returns.
  final List<String> values;
}

/// Modal that defines a runtime variable: a name and a comma-separated list of
/// the values it may take (issue #78). Unlike the pre-registry free-text guard
/// this replaces, a variable is an *enumerated* choice — so the edge condition
/// picker can offer `var · name = value` guards, and the variables bar can flip
/// it live between exactly these values.
///
/// Owns its controllers so their exit animation never outlives them (the same
/// "used after disposed" trap the chain rename dialog avoids). Returns `null`
/// on cancel or when no name / no values were given.
class RuntimeVariableDefineDialog extends StatefulWidget {
  const RuntimeVariableDefineDialog({
    this.initialName = '',
    this.initialValues = '',
    super.key,
  });

  final String initialName;

  /// Comma-separated candidate values to seed the values field with (used when
  /// redefining an existing variable).
  final String initialValues;

  @override
  State<RuntimeVariableDefineDialog> createState() =>
      _RuntimeVariableDefineDialogState();
}

class _RuntimeVariableDefineDialogState
    extends State<RuntimeVariableDefineDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _values = TextEditingController(
    text: widget.initialValues,
  );

  @override
  void dispose() {
    _name.dispose();
    _values.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final values = _parseValues(_values.text);
    if (name.isEmpty || values.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pop(RuntimeVariableDefinition(name: name, values: values));
  }

  /// Split on commas, trim, and drop blanks — so `high, low ,` yields
  /// `[high, low]`. Deduping is left to the registry.
  static List<String> _parseValues(String raw) => [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

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
            controller: _values,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            decoration: const InputDecoration(
              hintText: 'values, comma-separated (e.g. low, high)',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('define')),
      ],
    );
  }
}
