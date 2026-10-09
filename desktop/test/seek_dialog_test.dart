import 'package:cliamp_desktop/src/seek_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(
  WidgetTester tester, {
  required void Function(double?) onResult,
  double position = 20,
  double duration = 7200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                onResult(
                  await showSeekDialog(
                    context,
                    position: position,
                    duration: duration,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final example in <String, double>{
    '0': 0,
    '90': 90,
    '01:30': 90,
    '1:02:03': 3723,
    '120:00': 7200,
    ':49': 49,
    '58:': 3480,
    '1::03': 3603,
    ' 12:3 ': 723,
  }.entries) {
    testWidgets('accepts ${example.key} as ${example.value} seconds', (
      tester,
    ) async {
      final results = <double?>[];
      await _open(tester, onResult: results.add);
      await tester.enterText(find.byType(TextFormField), example.key);
      await tester.tap(find.text('Jump'));
      await tester.pumpAndSettle();
      expect(results, [example.value]);
      expect(find.text('Jump to time'), findsNothing);
    });
  }

  for (final input in [
    '',
    '-5',
    'NaN',
    'Infinity',
    '1:60',
    '1:60:00',
    '1:00:60',
    '1:2:3:4',
    '10:123',
    '7201',
  ]) {
    testWidgets('rejects invalid or out-of-range target "$input"', (
      tester,
    ) async {
      final results = <double?>[];
      await _open(tester, onResult: results.add);
      await tester.enterText(find.byType(TextFormField), input);
      await tester.tap(find.text('Jump'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(find.text('Jump to time'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        input,
      );
    });
  }

  testWidgets('cancel returns null without applying the entered target', (
    tester,
  ) async {
    final targets = <double>[];
    final results = <double?>[];
    await _open(
      tester,
      onResult: (target) {
        results.add(target);
        if (target != null) targets.add(target);
      },
    );
    await tester.enterText(find.byType(TextFormField), '50');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(targets, isEmpty);
  });

  testWidgets('Enter submits the current position and allows exact duration', (
    tester,
  ) async {
    final results = <double?>[];
    await _open(tester, onResult: results.add, position: 3723, duration: 3723);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '1:02:03',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(results, [3723]);
  });
}
