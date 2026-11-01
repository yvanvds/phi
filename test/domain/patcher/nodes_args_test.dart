import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/nodes_args.dart';

void main() {
  test('no argument is the engine default of four nodes', () {
    expect(NodesArgs.parse('').count, 4);
    expect(NodesArgs.parse('   ').count, 4);
  });

  test('the first number is the count, truncated and clamped to 1-64', () {
    expect(NodesArgs.parse('6').count, 6);
    expect(NodesArgs.parse('2.9').count, 2);
    expect(NodesArgs.parse('0').count, 1);
    expect(NodesArgs.parse('-3').count, 1);
    expect(NodesArgs.parse('99').count, 64);
    expect(NodesArgs.parse('foo 5').count, 5, reason: 'words are skipped');
  });
}
