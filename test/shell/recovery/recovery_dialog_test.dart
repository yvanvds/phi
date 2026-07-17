import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/recovery/recovery_offer.dart';
import 'package:phi/shell/recovery/recovery_dialog.dart';

void main() {
  // Drives the dialog through a real Navigator/showDialog, capturing what
  // `RecoveryDialog.show` resolves to for each button.
  Future<RecoveryChoice?> tapChoice(
    WidgetTester tester,
    RecoveryOffer offer,
    String label,
  ) async {
    RecoveryChoice? result;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  opened = true;
                  result = await RecoveryDialog.show(context, offer: offer);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('offers the three choices and resolves replay all', (
    tester,
  ) async {
    const offer = RecoveryOffer(entryCount: 3, crashLoop: false);
    // All three actions are present.
    await tester.pumpWidget(
      const MaterialApp(home: RecoveryDialog(offer: offer)),
    );
    expect(find.text('replay all'), findsOneWidget);
    expect(find.text('replay to previous'), findsOneWidget);
    expect(find.text('open last save'), findsOneWidget);
    expect(find.text('Recover unsaved work?'), findsOneWidget);
    // The count is surfaced to the performer.
    expect(find.textContaining('3 unsaved edits'), findsOneWidget);

    expect(
      await tapChoice(tester, offer, 'replay all'),
      RecoveryChoice.replayAll,
    );
  });

  testWidgets('resolves replay to previous', (tester) async {
    expect(
      await tapChoice(
        tester,
        const RecoveryOffer(entryCount: 2, crashLoop: false),
        'replay to previous',
      ),
      RecoveryChoice.replayToPrevious,
    );
  });

  testWidgets('resolves skip', (tester) async {
    expect(
      await tapChoice(
        tester,
        const RecoveryOffer(entryCount: 2, crashLoop: false),
        'open last save',
      ),
      RecoveryChoice.skipJournal,
    );
  });

  testWidgets('a crash-loop leads with the did-not-finish warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RecoveryDialog(
          offer: RecoveryOffer(entryCount: 1, crashLoop: true),
        ),
      ),
    );
    expect(find.text('Recovery did not finish'), findsOneWidget);
    expect(
      find.textContaining('previous recovery did not finish'),
      findsOneWidget,
    );
    // Singular wording for a single edit.
    expect(find.textContaining('1 unsaved edit'), findsOneWidget);
  });
}
