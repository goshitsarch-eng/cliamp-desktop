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
  await a.stage(t, 'history-replay-cancel-clear-and-repopulate', () async {
    await a.click(
      t,
      find.byTooltip(RegExp(r'^Play (Aurora - )?Blue Hour$')),
      'Play history fixture',
    );
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause history fixture');
    await a.click(
      t,
      find.byTooltip('Favorite current track'),
      'Favorite current',
    );
    await a.click(
      t,
      find.byTooltip('Favorite current track'),
      'Restore favorite',
    );
    await a.nav(t, 'History');
    await a.waitFor(t, find.byTooltip('Track actions'));
    await i.menu(t, 'Track actions', 'Track details');
    await a.click(t, find.text('Close'), 'Close historical details');
    await a.click(t, find.byTooltip('Clear history'), 'Clear history');
    await a.dialogSizes(t, 'clear-history');
    await a.click(t, find.text('Cancel'), 'Keep history');
    expect(find.byTooltip('Track actions').evaluate(), isNotEmpty);
    await a.click(t, find.byTooltip('Clear history'), 'Clear history again');
    await a.click(t, find.text('Clear'), 'Confirm history clear');
    expect(find.byTooltip('Track actions'), findsNothing);
    await a.nav(t, 'Queue');
    final title = find.textContaining(RegExp(r'^(Aurora - )?Blue Hour$')).first;
    await t.tap(title);
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(title);
    await a.tick(t);
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause double-click playback');
    await a.nav(t, 'History');
    await a.waitFor(t, find.byTooltip('Track actions'));
    await a.click(
      t,
      find.byTooltip(RegExp(r'^Play (Aurora - )?Blue Hour$')).first,
      'Replay history',
    );
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause historical playback');
  });
  await a.nav(t, 'Queue');
  await a.stage(t, 'unsupported-local-track-actions', () async {
    for (final action in ['Related tracks', 'Go to artist']) {
      await i.menu(t, 'Track actions', action);
      await a.waitFor(t, find.byType(SnackBar));
      await a.capture('local-${action.replaceAll(' ', '-')}');
    }
    for (final action in ['button', 'menu', 'shortcut']) {
      if (action == 'button') {
        await a.click(
          t,
          find.byTooltip('Download current track'),
          'Download local track',
        );
      } else if (action == 'menu') {
        await i.menu(t, 'Playback options', 'Download track');
      } else {
        await a.key(t, LogicalKeyboardKey.keyS, ctrl: true);
      }
      await a.waitFor(t, find.byType(SnackBar));
      await a.capture('local-download-$action');
    }
  });
}
