import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
  await a.stage(t, 'palette-enter-result', () async {
    await a.key(t, LogicalKeyboardKey.f1);
    await i.enter(t, i.field('Find a command'), 'Open Queue');
    await a.key(t, LogicalKeyboardKey.enter);
    expect(
      find.text('Commands & keyboard shortcuts'),
      findsNothing,
      reason: 'Enter should activate the matching command',
    );
  });
  for (final action in [
    'Play / pause',
    'Previous track',
    'Next track',
    'Seek back 10 seconds',
    'Seek forward 10 seconds',
    'Volume up / down',
    'Jump to time',
    'Add files, folder, or URL',
    'Search this view',
    'Download playing track',
    'Undo playlist / queue edit',
    'Compact player',
    'Toggle shuffle',
    'Cycle repeat',
  ]) {
    await a.stage(
      t,
      'palette-${action.replaceAll(RegExp(r'[^a-zA-Z]+'), '-')}',
      () async {
        if (action == 'Jump to time') {
          if ((await a.backend.snapshot())['seekable'] != true) {
            await a.click(
              t,
              find.byTooltip(RegExp(r'^Play (Aurora - )?Blue Hour$')),
              'Start seekable track',
            );
          }
          if (find.byTooltip('Pause').evaluate().isNotEmpty) {
            await a.click(t, find.byTooltip('Pause'), 'Pause seekable track');
          }
        }
        await a.key(t, LogicalKeyboardKey.f1);
        await i.enter(t, i.field('Find a command'), action);
        await a.click(
          t,
          find.widgetWithText(ListTile, action),
          'Execute $action',
        );
        expect(find.text('Commands & keyboard shortcuts'), findsNothing);
        if (action == 'Jump to time' || action == 'Add files, folder, or URL') {
          await a.click(t, find.text('Cancel'), 'Cancel palette dialog');
        } else if (action == 'Compact player') {
          expect(find.text('Open library'), findsOneWidget);
          await a.click(t, find.text('Open library'), 'Return to library');
        } else if (action == 'Search this view') {
          await a.key(t, LogicalKeyboardKey.escape);
        }
        a.results.add({
          'stage': a.current,
          'stateAfterAction': await a.backend.snapshot(),
        });
      },
    );
  }
  await a.stage(t, 'keyboard-transport-and-text-editing', () async {
    await a.key(t, LogicalKeyboardKey.escape);
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await a.key(t, key, ctrl: true);
    }
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await a.key(t, key);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    }
    await a.key(t, LogicalKeyboardKey.keyF, ctrl: true);
    await i.enter(t, i.hint('Search your music…'), 'ab');
    await a.key(t, LogicalKeyboardKey.backspace);
    expect(
      t.widget<TextField>(i.hint('Search your music…')).controller!.text,
      'a',
    );
    await a.key(t, LogicalKeyboardKey.home);
    await a.key(t, LogicalKeyboardKey.delete);
    expect(
      t.widget<TextField>(i.hint('Search your music…')).controller!.text,
      isEmpty,
    );
    await a.key(t, LogicalKeyboardKey.escape);
  });
}
