import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shell_layout/shell_layout.dart';
import 'package:phi/shell/layout/splitter_resize.dart';

/// Unit tests for the pure splitter maths (design §2 — "resizes sibling fractions
/// with sensible minima"): only the flanking pair moves, the sum is preserved,
/// and both flanks are pinned at [ShellLayout.minFraction].
void main() {
  double sum(List<double> f) => f.fold(0, (a, b) => a + b);

  test('grows the leading pane and shrinks its neighbour, sum preserved', () {
    final out = resizeSiblings(
      fractions: [0.5, 0.5],
      leadingIndex: 0,
      deltaFraction: 0.1,
    );

    expect(out[0], closeTo(0.6, 1e-9));
    expect(out[1], closeTo(0.4, 1e-9));
    expect(sum(out), closeTo(1, 1e-9));
  });

  test('only the flanking pair moves; distant siblings are untouched', () {
    final out = resizeSiblings(
      fractions: [0.25, 0.25, 0.5],
      leadingIndex: 0,
      deltaFraction: 0.1,
    );

    expect(out[0], closeTo(0.35, 1e-9));
    expect(out[1], closeTo(0.15, 1e-9));
    expect(out[2], closeTo(0.5, 1e-9), reason: 'untouched');
    expect(sum(out), closeTo(1, 1e-9));
  });

  test('clamps the shrinking leading pane at the minimum on a hard drag', () {
    final out = resizeSiblings(
      fractions: [0.5, 0.5],
      leadingIndex: 0,
      deltaFraction: -5, // drag far past the edge
    );

    expect(out[0], closeTo(ShellLayout.minFraction, 1e-9));
    expect(out[1], closeTo(1 - ShellLayout.minFraction, 1e-9));
  });

  test('clamps the shrinking trailing pane at the minimum on a hard drag', () {
    final out = resizeSiblings(
      fractions: [0.5, 0.5],
      leadingIndex: 0,
      deltaFraction: 5,
    );

    expect(out[0], closeTo(1 - ShellLayout.minFraction, 1e-9));
    expect(out[1], closeTo(ShellLayout.minFraction, 1e-9));
  });

  test('a pair too small for two minima is left unchanged', () {
    final fractions = [0.05, 0.05, 0.9];
    final out = resizeSiblings(
      fractions: fractions,
      leadingIndex: 0,
      deltaFraction: 0.02,
    );

    expect(out, same(fractions));
  });

  test('an out-of-range handle index is a no-op', () {
    final fractions = [0.5, 0.5];
    expect(
      resizeSiblings(fractions: fractions, leadingIndex: 1, deltaFraction: 0.1),
      same(fractions),
    );
    expect(
      resizeSiblings(
        fractions: fractions,
        leadingIndex: -1,
        deltaFraction: 0.1,
      ),
      same(fractions),
    );
  });

  test('a zero delta returns the list unchanged (identity)', () {
    final fractions = [0.5, 0.5];
    expect(
      resizeSiblings(fractions: fractions, leadingIndex: 0, deltaFraction: 0),
      same(fractions),
    );
  });
}
