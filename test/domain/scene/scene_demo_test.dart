import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/scene_demo.dart';
import 'package:phi/domain/scene/scene_field.dart';

/// The pick-friendly Scene demo set (issue #90) must be a handful of agents
/// that are trivial to isolate by hand: well beyond the pick radius apart, each
/// on its own voice colour, sitting still. These are the properties that make
/// the awkward playback demo (short, clustered notes) unnecessary for manually
/// exercising pick / select / grab.
void main() {
  group('pickDemoAgents (issue #90)', () {
    test('is a small handful of agents', () {
      final agents = pickDemoAgents();
      expect(agents.length, inInclusiveRange(3, 8));
    });

    test('every pair is well beyond the pick radius apart', () {
      final agents = pickDemoAgents();
      // A wide margin over the pick sphere so a stray click never lands on two
      // agents at once — the whole point of the preset.
      const minSeparation = 2.0;
      expect(minSeparation, greaterThan(SceneField.defaultPickRadius * 2));
      for (var i = 0; i < agents.length; i++) {
        for (var j = i + 1; j < agents.length; j++) {
          final d = agents[i].position.distanceTo(agents[j].position);
          expect(
            d,
            greaterThan(minSeparation),
            reason: 'agents $i and $j sit only $d apart',
          );
        }
      }
    });

    test('each agent carries a distinct voice colour', () {
      final voices = pickDemoAgents().map((a) => a.voiceIndex).toList();
      expect(voices.toSet().length, voices.length);
      for (final v in voices) {
        expect(v, inInclusiveRange(0, 5)); // voice1..voice6 palette
      }
    });

    test('agents sit still with finite positions', () {
      for (final a in pickDemoAgents()) {
        expect(a.velocity.length, 0);
        expect(a.position.x.isFinite && a.position.y.isFinite, isTrue);
        expect(a.position.z.isFinite, isTrue);
      }
    });
  });
}
