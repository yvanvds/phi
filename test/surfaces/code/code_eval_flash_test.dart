import 'package:flutter_test/flutter_test.dart';
import 'package:phi/surfaces/code/code_eval_flash.dart';

void main() {
  // CodeEvalFlash.fire() starts a Ticker, which needs an initialized binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh flash defaults to the ok (clean) kind', () {
    final flash = CodeEvalFlash();
    addTearDown(flash.dispose);

    flash.fire(startLine: 2, endLine: 4);

    expect(flash.kind, CodeEvalFlashKind.ok);
    expect(flash.intensity, 1.0);
    expect(flash.covers(3), isTrue);
    expect(flash.covers(5), isFalse);
  });

  test('firing with the error kind paints the block red', () {
    final flash = CodeEvalFlash();
    addTearDown(flash.dispose);

    flash.fire(startLine: 0, endLine: 1, kind: CodeEvalFlashKind.error);

    expect(flash.kind, CodeEvalFlashKind.error);
    expect(flash.covers(1), isTrue);
  });

  test('a later ok flash replaces an earlier error kind', () {
    final flash = CodeEvalFlash();
    addTearDown(flash.dispose);

    flash.fire(startLine: 0, endLine: 0, kind: CodeEvalFlashKind.error);
    flash.fire(startLine: 5, endLine: 6);

    expect(flash.kind, CodeEvalFlashKind.ok);
    expect(flash.startLine, 5);
  });
}
