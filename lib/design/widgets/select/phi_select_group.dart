import 'phi_select_option.dart';

/// A run of [options] in a `PhiSelect<T>`, optionally under a [label] header.
///
/// A flat list is one headerless group (see `PhiSelect.flat`); a grouped list —
/// audio devices grouped by host, say — is several groups, each with its host
/// name as the header. Headers are non-selectable and skipped by keyboard
/// navigation.
class PhiSelectGroup<T> {
  const PhiSelectGroup({this.label, required this.options});

  /// The header shown above [options], or `null` for a headerless run.
  final String? label;

  /// The selectable rows in this group, in display order.
  final List<PhiSelectOption<T>> options;
}
