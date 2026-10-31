import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/label_switch_args.dart';

/// [LabelSwitchArgs] reads `.led` / `.textbutton` arguments the way the
/// engine's `gLabelSwitchBase` does (issue #470).
void main() {
  test('no arguments is an unlabelled latch', () {
    final a = LabelSwitchArgs.parse('');
    expect(a.momentary, isFalse);
    expect(a.label, '');
  });

  test('every word is the label, joined with single spaces', () {
    final a = LabelSwitchArgs.parse('  filter   cutoff ');
    expect(a.momentary, isFalse);
    expect(a.label, 'filter cutoff');
  });

  test('a leading momentary is the mode, not the label', () {
    final a = LabelSwitchArgs.parse('momentary go');
    expect(a.momentary, isTrue);
    expect(a.label, 'go');
  });

  test('momentary anywhere else is part of the label', () {
    final a = LabelSwitchArgs.parse('not momentary');
    expect(a.momentary, isFalse);
    expect(a.label, 'not momentary');
  });
}
