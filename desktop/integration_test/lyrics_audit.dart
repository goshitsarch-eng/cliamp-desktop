import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await a.stage(t, 'synced-lyrics-seek-offset-follow', () async {
    await i.loadSources(t, '${a.root}/profile/home/Music/Audit lyrics.flac');
    await a.click(
      t,
      find.byTooltip('Play Audit lyrics'),
      'Play tagged lyrics fixture',
    );
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause lyric track');
    await a.nav(t, 'Lyrics');
    await a.waitFor(t, find.text('First Café 春 line'));
    await a.click(t, find.text('Second line'), 'Seek through lyrics');
    expect((await a.backend.snapshot())['position'], closeTo(30, 1));
    await a.click(t, find.byTooltip('Advance lyrics 250 ms'), 'Advance lyrics');
    expect((await a.backend.snapshot())['lyrics_offset_ms'], 250);
    await a.click(t, find.byTooltip('Delay lyrics 250 ms'), 'Delay lyrics');
    expect((await a.backend.snapshot())['lyrics_offset_ms'], 0);
    for (var n = 0; n < 2; n++) {
      await a.click(
        t,
        find.widgetWithText(FilterChip, 'Follow lyrics'),
        'Toggle lyric following',
      );
    }
    await a.resize(t, 640, 480);
    await a.tick(t, 500);
    final active = t.getRect(find.text('Second line'));
    final player = t
        .widget<Scaffold>(find.byType(Scaffold).last)
        .bottomNavigationBar!;
    final playerRect = t.getRect(find.byWidget(player));
    expect(
      active.bottom,
      lessThanOrEqualTo(playerRect.top),
      reason:
          'Following must keep the active line above the player after resize',
    );
    await a.capture('synced-lyrics-active-minimum');
    await a.dialogSizes(t, 'synced-lyrics');
    await a.click(
      t,
      find.byTooltip('Refresh lyrics'),
      'Refresh embedded lyrics',
    );
    await a.waitFor(t, find.text('Final line'));
  });
  await a.nav(t, 'Queue');
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
}
