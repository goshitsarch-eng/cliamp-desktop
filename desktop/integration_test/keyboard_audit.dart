import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await a.stage(t, 'native-maximize-restore', () async {
    for (final action in ['maximize', 'restore']) {
      final r = await Process.run('python3', [
        '${a.root}/window.py',
        action,
        a.window,
      ]);
      expect(r.exitCode, 0);
      await a.tick(t, 500);
      if (action == 'maximize') {
        expect(t.view.physicalSize.width, greaterThan(1600));
      }
      await a.capture('window-$action');
    }
    await a.resize(t, 1280, 940);
  });

  await a.stage(t, 'linux-media-controls', () async {
    expect(
      Platform.environment['DBUS_SESSION_BUS_ADDRESS'],
      isNotNull,
      reason: 'Run the native audit under dbus-run-session',
    );
    for (final method in [
      'Play',
      'Pause',
      'Next',
      'Previous',
      'PlayPause',
      'Stop',
    ]) {
      final result = await Process.run('dbus-send', [
        '--session',
        '--print-reply',
        '--dest=org.mpris.MediaPlayer2.cliamp',
        '/org/mpris/MediaPlayer2',
        'org.mpris.MediaPlayer2.Player.$method',
      ]);
      expect(result.exitCode, 0, reason: '$method: ${result.stderr}');
      await a.tick(t);
      a.results.add({
        'stage': a.current,
        'mediaControl': method,
        'state': await a.backend.snapshot(),
      });
    }
    expect((await a.backend.snapshot())['state'], 'stopped');
  });

  await a.stage(t, 'playback-speed-repeat-volume-and-keys', () async {
    for (final speed in [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0, 1.0]) {
      await a.click(
        t,
        find.byTooltip('Playback speed').first,
        'Playback speed',
      );
      await a.click(
        t,
        find.widgetWithText(PopupMenuItem<double>, '$speed×'),
        'Speed $speed',
      );
      expect((await a.backend.snapshot())['speed'], speed);
    }
    for (
      var n = 0;
      n < 3 && (await a.backend.snapshot())['repeat'] != 'Off';
      n++
    ) {
      final current = (await a.backend.snapshot())['repeat'];
      await a.click(t, find.byTooltip('Repeat: $current'), 'Normalize repeat');
    }
    for (final repeat in ['Off', 'All', 'One']) {
      await a.click(
        t,
        find.byTooltip('Repeat: $repeat'),
        'Cycle repeat $repeat',
      );
    }
    await a.click(t, find.byTooltip('Minimum volume'), 'Minimum volume');
    await a.click(t, find.byTooltip('Restore volume'), 'Restore volume');
    final slider = find.byWidgetPredicate((w) => w is Slider && w.max == 6);
    final volumeBefore = (await a.backend.snapshot())['volume'];
    await t.drag(slider, const Offset(-15, 0));
    await a.tick(t);
    expect((await a.backend.snapshot())['volume'], isNot(volumeBefore));
    await a.key(t, LogicalKeyboardKey.keyF, ctrl: true);
    await i.enter(t, i.hint('Search your music…'), ' ');
    final before = (await a.backend.snapshot())['state'];
    await a.key(t, LogicalKeyboardKey.space);
    expect(
      (await a.backend.snapshot())['state'],
      before,
      reason: 'Typing spaces must not toggle playback',
    );
    await a.key(t, LogicalKeyboardKey.escape);
    await a.key(t, LogicalKeyboardKey.tab);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await a.key(t, LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await a.key(t, LogicalKeyboardKey.keyX, ctrl: true);
    expect(find.text('Open library'), findsOneWidget);
    await a.resize(t, 640, 480);
    await a.capture('compact-player-minimum');
    await a.resize(t, 1280, 940);
    await a.click(t, find.text('Open library'), 'Return from compact player');
  });
  for (final page in a.pages) {
    await a.stage(t, 'palette-open-${page.replaceAll(' ', '-')}', () async {
      await a.key(t, LogicalKeyboardKey.keyK, ctrl: true);
      await i.enter(t, i.field('Find a command'), 'Open $page');
      await a.click(
        t,
        find.widgetWithText(ListTile, 'Open $page'),
        'Palette Open $page',
      );
      expect(find.text('Commands & keyboard shortcuts'), findsNothing);
    });
  }
  await a.nav(t, 'Settings');
  await a.stage(t, 'settings-mono-device-help-and-operations', () async {
    await a.click(t, find.text('Mono audio'), 'Mono on');
    await a.click(t, find.text('Mono audio'), 'Mono off');
    await a.click(
      t,
      find.byTooltip('Refresh audio devices'),
      'Refresh devices',
    );
    await a.reveal(t, find.text('Setup instructions'));
    await a.click(t, find.text('Setup instructions'), 'Provider help');
    await a.click(t, find.text('Close'), 'Close help');
    final browse = find.textContaining('engine operations');
    await a.reveal(t, browse);
    await a.click(t, browse, 'Browse engine operations');
    await a.dialogSizes(t, 'engine-operations');
    await a.capture('engine-operations-open');
    final operationPicker = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(DropdownButton<String>),
    );
    final operations = t
        .widget<DropdownButton<String>>(operationPicker)
        .items!
        .map((item) => item.value!)
        .toList();
    for (final operation
        in Platform.environment['CLIAMP_AUDIT_OPERATIONS_FAST'] == '1'
            ? <String>[]
            : operations) {
      await i.choose(t, operationPicker, operation);
      expect(
        t.widget<DropdownButton<String>>(operationPicker).value,
        operation,
      );
    }
    await i.choose(t, operationPicker, 'queue.list');
    await i.enter(t, i.field('Parameters (JSON object)'), '[]');
    await a.click(t, find.text('Run operation'), 'Reject JSON array');
    expect(find.textContaining('Enter a JSON object.'), findsOneWidget);
    await a.capture('engine-json-validation');
    await i.enter(t, i.field('Parameters (JSON object)'), '{"limit":10}');
    await a.click(t, find.text('Run operation'), 'Run queue query');
    await a.waitFor(t, find.text('Operation result'));
    await a.click(t, find.text('Close'), 'Close operation result');
  });
  await a.stage(t, 'background-activity', () async {
    await a.click(
      t,
      find.byTooltip('Background activity'),
      'Background activity',
    );
    await a.dialogSizes(t, 'background-activity');
    await a.click(t, find.text('Close'), 'Close activity');
  });
}
