/// Why a candidate registry name was rejected by [NameValidator].
///
/// Returned (as a nullable) by [NameValidator.check] so a create/rename dialog
/// can show the reason inline. The [message] is a short, user-facing sentence;
/// the enum value itself is what tests and callers branch on.
enum NameProblem {
  /// The name was the empty string.
  empty('A name cannot be empty.'),

  /// The name exceeded [NameValidator.maxLength] characters.
  tooLong('A name may be at most 64 characters.'),

  /// The name is not lowercase `snake_case` — it must match
  /// `[a-z_][a-z0-9_]*` (ASCII lowercase, digits and underscores, never
  /// leading with a digit).
  malformed(
    'A name must be lowercase snake_case (letters, digits, '
    'underscores; not starting with a digit).',
  ),

  /// The name is a reserved Python keyword and so cannot follow a dot in the
  /// generated Python attribute chain (e.g. `class`, `for`, `def`).
  pythonKeyword('A name cannot be a Python keyword.'),

  /// The name is a Windows reserved device name (`con`, `prn`, `aux`, `nul`,
  /// `com1`–`com9`, `lpt1`–`lpt9`) — a file named after one misbehaves.
  reservedDeviceName('A name cannot be a Windows reserved device name.');

  const NameProblem(this.message);

  /// A short, user-facing explanation, suitable for a form field's error text.
  final String message;
}
