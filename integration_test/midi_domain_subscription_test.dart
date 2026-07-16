import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end subscription-as-clock-binding through the real workstation
/// (issue #102).
///
/// The `domain · drum @ 124` chip in the default chain is a real
/// [DomainSubscriptionTransform]. Since #102 a subscription is a **clock
/// choice, not a note rewrite**: with the chip on, the engine transport's clock
/// binds to the `drum` domain's 124 BPM; with it off, the clip falls back to the
/// session's 120. Crucially the *pushed note times never move* either way —
/// tempo lives in the clock, not the data, so a live tempo change never forces a
/// re-evaluate/re-push. This drives that whole path through real navigation and
/// the real session → shell → player wiring, with a [FakeMidiGateway] recording
/// the transport the player mints (its clock tempo and its pushed events).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets(
    'midi: the domain chip binds the transport clock, not the notes',
    (tester) async {
      final midiGateway = FakeMidiGateway();
      final engine = PhiEngine(
        FakeYseGateway(),
        midiGateway: midiGateway,
        telemetryInterval: const Duration(milliseconds: 20),
      );
      final session = SessionState(); // session tempo defaults to 120

      await tester.pumpWidget(PhiApp(engine: engine, session: session));
      await tester.pumpAndSettle();

      // Open the MIDI surface; the seed chain has the domain chip active.
      await tester.tap(railFor(SurfaceId.midi));
      await tester.pumpAndSettle();
      expect(find.text('domain · drum @ 124'), findsOneWidget);

      // Play through the real session → shell → player path. Use pump, not
      // pumpAndSettle — the looping playhead timer never settles.
      session.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // The chip is on: the transport clock is bound to the drum domain's 124,
      // not the session's 120. The note beats were pushed as authored.
      final transport = midiGateway.transport;
      expect(transport, isNotNull);
      expect(transport!.isPlaying, isTrue);
      expect(
        transport.tempo,
        124,
        reason: 'an active subscription binds the clock to the domain tempo',
      );
      final subscribedStarts = transport.events
          .map((e) => e.startBeat)
          .toList(growable: false);
      expect(subscribedStarts, isNotEmpty);

      // Toggle the domain chip off. The next tick re-binds the clock to the
      // session tempo — but re-pushes the *same* note times, because a
      // subscription only chooses a clock, it never rewrites the beats.
      await tester.tap(find.text('domain · drum @ 124'));
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        transport.tempo,
        120,
        reason: 'toggling the chip off falls back to the session tempo',
      );
      final unsubscribedStarts = transport.events
          .map((e) => e.startBeat)
          .toList(growable: false);
      expect(
        unsubscribedStarts,
        subscribedStarts,
        reason: 'the subscription binds the clock; it does not move note times',
      );

      session.stop();
      await tester.pump(const Duration(milliseconds: 20));
      expect(transport.isPlaying, isFalse);

      session.dispose();
      await engine.dispose();
    },
  );
}
