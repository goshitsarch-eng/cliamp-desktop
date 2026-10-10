import 'package:cliamp_desktop/src/lyrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('following keeps the active lyric visible after resizing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: const SizedBox(height: 148),
          body: SyncedLyrics(
            lines: const [
              {'start': 0, 'text': 'First line'},
              {'start': 30, 'text': 'Second line'},
              {'start': 60, 'text': 'Final line'},
            ],
            position: 30,
            realtime: false,
            seekable: true,
            onSeek: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(640, 340);
    await tester.pumpAndSettle();
    final active = tester.getRect(find.text('Second line'));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(active.top, greaterThanOrEqualTo(viewport.top));
    expect(active.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });
}
