import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/session/transport_state.dart';
import 'package:phi/shell/top_toolbar/top_toolbar.dart';

void main() {
  Future<void> pumpToolbar(WidgetTester tester, SessionState session) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TopToolbar(session: session)),
      ),
    );
  }

  testWidgets('exposes stable, unique keys for the transport buttons', (
    tester,
  ) async {
    final session = SessionState();
    addTearDown(session.dispose);

    await pumpToolbar(tester, session);

    // The toolbar's play/stop must be uniquely targetable by key — the MIDI
    // surface renders its own `play`/`stop` tooltips, so a tooltip finder is
    // ambiguous once MIDI is onstage (issues #288/#290/#292). These keys give
    // tests an unambiguous handle regardless of what else is on stage.
    expect(find.byKey(TopToolbar.playKey), findsOneWidget);
    expect(find.byKey(TopToolbar.stopKey), findsOneWidget);
  });

  testWidgets('play and stop keys drive the session transport', (tester) async {
    final session = SessionState();
    addTearDown(session.dispose);

    await pumpToolbar(tester, session);
    expect(session.transport.value, TransportState.idle);

    await tester.tap(find.byKey(TopToolbar.playKey));
    await tester.pump();
    expect(session.transport.value, TransportState.playing);

    await tester.tap(find.byKey(TopToolbar.stopKey));
    await tester.pump();
    expect(session.transport.value, TransportState.idle);
  });
}
