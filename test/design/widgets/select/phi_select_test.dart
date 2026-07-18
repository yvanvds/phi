import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
import 'package:phi/design/widgets/select/phi_select_group.dart';
import 'package:phi/design/widgets/select/phi_select_option.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );

  const key = ValueKey('select');

  // A flat rate picker whose first entry is the "device default" (null value).
  Widget flatSelect({
    int? value,
    required ValueChanged<int?>? onChanged,
    bool enabled = true,
  }) => host(
    PhiSelect<int?>.flat(
      key: key,
      value: value,
      enabled: enabled,
      options: const [
        PhiSelectOption(value: null, label: 'device default'),
        PhiSelectOption(value: 44100, label: '44100 Hz'),
        PhiSelectOption(value: 48000, label: '48000 Hz'),
      ],
      onChanged: onChanged,
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  group('flat list', () {
    testWidgets('shows the placeholder when nothing is selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PhiSelect<int?>.flat(
            key: key,
            value: 999, // matches no option
            placeholder: 'pick one',
            options: const [PhiSelectOption(value: 1, label: 'one')],
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('pick one'), findsOneWidget);
    });

    testWidgets('opens on tap and lists every option', (tester) async {
      await tester.pumpWidget(flatSelect(value: null, onChanged: (_) {}));
      await open(tester);

      expect(find.text('44100 Hz'), findsOneWidget);
      expect(find.text('48000 Hz'), findsOneWidget);
    });

    testWidgets('tapping an option emits its value and closes', (tester) async {
      int? picked;
      var calls = 0;
      await tester.pumpWidget(
        flatSelect(
          value: null,
          onChanged: (v) {
            picked = v;
            calls++;
          },
        ),
      );
      await open(tester);

      await tester.tap(find.text('48000 Hz'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(picked, 48000);
      // Menu is dismissed: the option row is gone.
      expect(find.text('44100 Hz'), findsNothing);
    });

    testWidgets('an outside tap dismisses without emitting', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        flatSelect(value: null, onChanged: (_) => calls++),
      );
      await open(tester);
      expect(find.text('44100 Hz'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('44100 Hz'), findsNothing);
    });
  });

  group('device default first entry', () {
    testWidgets('renders the default label in the closed control', (
      tester,
    ) async {
      await tester.pumpWidget(flatSelect(value: null, onChanged: (_) {}));
      // Closed control shows the null option's label.
      expect(find.text('device default'), findsOneWidget);
    });

    testWidgets('selecting the default entry emits a null value', (
      tester,
    ) async {
      int? picked = 48000;
      var calls = 0;
      await tester.pumpWidget(
        flatSelect(
          value: 48000,
          onChanged: (v) {
            picked = v;
            calls++;
          },
        ),
      );
      await open(tester);

      await tester.tap(find.text('device default'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(picked, isNull);
    });
  });

  group('preselected value', () {
    testWidgets('shows the selected label and marks it in the open list', (
      tester,
    ) async {
      await tester.pumpWidget(flatSelect(value: 44100, onChanged: (_) {}));

      // Closed: the selected label shows.
      expect(find.text('44100 Hz'), findsOneWidget);

      await open(tester);
      // Exactly one row carries the selected check mark.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  group('grouped list', () {
    Widget groupedSelect({String? value, ValueChanged<String>? onChanged}) =>
        host(
          PhiSelect<String>(
            key: key,
            value: value,
            groups: const [
              PhiSelectGroup(
                label: 'ASIO',
                options: [
                  PhiSelectOption(value: 'ff-asio', label: 'Fireface UCX'),
                ],
              ),
              PhiSelectGroup(
                label: 'WASAPI',
                options: [PhiSelectOption(value: 'spk', label: 'Speakers')],
              ),
            ],
            onChanged: onChanged ?? (_) {},
          ),
        );

    testWidgets('renders group headers uppercased', (tester) async {
      await tester.pumpWidget(groupedSelect(value: null));
      await open(tester);

      expect(find.text('ASIO'), findsOneWidget);
      expect(find.text('WASAPI'), findsOneWidget);
      expect(find.text('Fireface UCX'), findsOneWidget);
      expect(find.text('Speakers'), findsOneWidget);
    });

    testWidgets('an option under a header is selectable', (tester) async {
      String? picked;
      await tester.pumpWidget(
        groupedSelect(value: null, onChanged: (v) => picked = v),
      );
      await open(tester);

      await tester.tap(find.text('Speakers'));
      await tester.pumpAndSettle();

      expect(picked, 'spk');
    });
  });

  group('keyboard navigation', () {
    testWidgets('arrow-down then enter commits the next option', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        flatSelect(value: null, onChanged: (v) => picked = v),
      );
      await open(tester); // highlight starts at index 0 (device default)

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // -> 44100
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(picked, 44100);
    });

    testWidgets('highlight clamps at the top with arrow-up', (tester) async {
      int? picked;
      await tester.pumpWidget(
        flatSelect(value: null, onChanged: (v) => picked = v),
      );
      await open(tester);

      // Already at index 0; arrow-up must not underflow.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(picked, isNull); // still the first (device default) option
    });

    testWidgets('escape dismisses without emitting', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        flatSelect(value: null, onChanged: (_) => calls++),
      );
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('44100 Hz'), findsNothing);
    });
  });

  group('disabled', () {
    testWidgets('a null onChanged does not open on tap', (tester) async {
      await tester.pumpWidget(flatSelect(value: 44100, onChanged: null));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();

      // The list never appears (only the closed control's label remains).
      expect(find.text('48000 Hz'), findsNothing);
    });

    testWidgets('enabled:false does not open on tap', (tester) async {
      await tester.pumpWidget(
        flatSelect(value: 44100, enabled: false, onChanged: (_) {}),
      );
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();

      expect(find.text('48000 Hz'), findsNothing);
    });

    testWidgets('disabled control paints muted foreground', (tester) async {
      await tester.pumpWidget(flatSelect(value: 44100, onChanged: null));

      final icon = tester.widget<Icon>(find.byIcon(Icons.keyboard_arrow_down));
      expect(icon.color, PhiColors.fg3);
    });
  });
}
