import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> operation(
  WidgetTester t,
  String name,
  Map<String, dynamic> params,
) async {
  await a.nav(t, 'Settings');
  final browse = find.textContaining('engine operations');
  await a.reveal(t, browse);
  await a.click(t, browse, 'Open engine operations for $name');
  final picker = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(DropdownButton<String>),
  );
  await i.choose(t, picker, name);
  await i.enter(t, i.field('Parameters (JSON object)'), jsonEncode(params));
  await a.click(t, find.text('Run operation'), 'Run $name fixture operation');
  await a.waitFor(t, find.text('Operation result'));
  await a.click(t, find.text('Close'), 'Close $name result');
}

Future<String> fixture(String name, String lyrics) async {
  final path = '${a.root}/profile/$name.flac';
  final result = await Process.run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    '${a.root}/profile/home/Music/Aurora - Blue Hour.wav',
    '-metadata',
    'lyrics=$lyrics',
    path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return path;
}

Future<void> exercise(WidgetTester t, {bool sections = true}) async {
  if (sections) {
    await a.nav(t, 'Settings');
    await t.scrollUntilVisible(
      find.text('All preferences'),
      -300,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 20,
    );
    await a.click(t, find.text('All preferences'), 'Open preference sections');
    final schema = await a.backend.preferencesSchema();
    final groups = (schema['fields'] as List)
        .map((f) => '${(f as Map)['group']}')
        .toSet();
    for (final group in groups) {
      await a.stage(t, 'preference-section-$group', () async {
        await i.enter(t, i.hint('Find a preference'), group);
        final section = find.byKey(ValueKey('$group:${group.toLowerCase()}'));
        final title = find
            .descendant(of: section, matching: find.text(group))
            .first;
        await a.click(t, title, 'Collapse $group section');
        expect(
          find.descendant(of: section, matching: find.byType(TextField)),
          findsNothing,
        );
        await a.click(t, title, 'Expand $group section');
        await a.dialogSizes(t, 'preference-section-$group');
      });
    }
    await a.click(t, find.text('Done'), 'Close preference sections');
  }
  await operation(t, 'repeat', {'name': 'one'});
  for (final live in [false, true]) {
    await a.stage(
      t,
      live ? 'live-labelled-lyrics' : 'untimed-lyrics',
      () async {
        await operation(t, 'tracks.replace', {
          'tracks': [
            {
              'path': await fixture(
                live ? 'live-lyrics' : 'untimed-lyrics',
                live
                    ? '[00:00.00]Live first line\n[00:30.00]Live second line'
                    : 'Untimed Café 春 line\nSecond untimed line',
              ),
              'title': live ? 'Live labelled fixture' : 'Untimed fixture',
              'artist': 'Audit',
              'realtime': live,
              'embedded_lyrics': live
                  ? '[00:00.00]Live first line\n[00:30.00]Live second line'
                  : 'Untimed Café 春 line\nSecond untimed line',
            },
          ],
          'play': true,
        });
        await a.nav(t, 'Queue');
        await a.waitFor(t, find.byTooltip('Pause'));
        await a.click(t, find.byTooltip('Pause'), 'Pause fixture playback');
        await a.nav(t, 'Lyrics');
        final line = live ? 'Live first line' : 'Untimed Café 春 line';
        await a.waitFor(t, find.text(line));
        expect(find.text('Follow lyrics'), findsNothing);
        expect(find.byTooltip('Advance lyrics 250 ms'), findsNothing);
        final ink = find
            .ancestor(of: find.text(line), matching: find.byType(InkWell))
            .first;
        expect(
          t.widget<InkWell>(ink).onTap,
          isNull,
          reason:
              'Untimed/live lyrics must not expose a misleading seek action',
        );
        if (live) {
          expect(
            find.text('Live stream · lyrics shown without timing'),
            findsOneWidget,
          );
          expect((await a.backend.snapshot())['track']['realtime'], isTrue);
        }
        await a.dialogSizes(t, live ? 'live-lyrics' : 'untimed-lyrics');
        await a.click(
          t,
          find.byTooltip('Refresh lyrics'),
          'Refresh lyric variant',
        );
        await a.waitFor(t, find.text(line));
      },
    );
  }
  await operation(t, 'tracks.replace', {
    'tracks': [
      {
        'path': await fixture(
          'boundary-lyrics',
          '[00:00.00]Boundary first line\n[00:30.00]Boundary second line',
        ),
        'title': 'Offset boundary fixture',
        'artist': 'Audit',
        'embedded_lyrics':
            '[00:00.00]Boundary first line\n[00:30.00]Boundary second line',
      },
    ],
    'play': true,
  });
  await a.nav(t, 'Queue');
  await a.waitFor(t, find.byTooltip('Pause'));
  await a.click(t, find.byTooltip('Pause'), 'Pause boundary fixture');
  for (final upper in [false, true]) {
    await a.stage(
      t,
      upper ? 'lyrics-offset-upper-bound' : 'lyrics-offset-lower-bound',
      () async {
        await operation(t, 'lyrics.offset', {'value': upper ? 9750 : -9750});
        await a.nav(t, 'Lyrics');
        await a.waitFor(t, find.text('Boundary first line'));
        final direction = upper
            ? 'Advance lyrics 250 ms'
            : 'Delay lyrics 250 ms';
        await a.click(t, find.byTooltip(direction), 'Reach lyric offset bound');
        expect(
          (await a.backend.snapshot())['lyrics_offset_ms'],
          upper ? 10000 : -10000,
        );
        final control = find.byTooltip(direction);
        expect(a.disabled(control), isTrue);
        await a.click(
          t,
          find.byTooltip(
            upper ? 'Delay lyrics 250 ms' : 'Advance lyrics 250 ms',
          ),
          'Return from lyric offset bound',
        );
        expect(
          (await a.backend.snapshot())['lyrics_offset_ms'],
          upper ? 9750 : -9750,
        );
      },
    );
  }
  await operation(t, 'lyrics.offset', {'value': 0});
  await operation(t, 'repeat', {'name': 'off'});
}
