import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  final music = '${a.root}/profile/home/Music';
  for (final source in [
    'missing.wav',
    'broken.m3u',
    'not-audio.txt',
    'x' * 4000,
  ]) {
    await a.stage(
      t,
      'source-error-${source.length > 100 ? 'long-path' : source}',
      () async {
        final before = (await a.backend.snapshot())['total'];
        await i.loadSources(t, '$music/$source', replace: true);
        expect(
          (await a.backend.snapshot())['total'],
          before,
          reason: 'Failed replacement must preserve queue',
        );
        expect(find.byType(SnackBar), findsOneWidget);
        await a.resize(t, 640, 480);
        await a.capture(
          'source-error-${source.length > 100 ? 'long' : source}-minimum',
        );
        await a.resize(t, 1280, 940);
        final close = find.descendant(
          of: find.byType(SnackBar),
          matching: find.byTooltip('Close'),
        );
        if (close.evaluate().isNotEmpty) {
          await a.click(t, close, 'Dismiss error');
        }
      },
    );
  }
  await a.stage(t, 'playlist-file-import-replace-cancel', () async {
    await a.key(t, LogicalKeyboardKey.keyO, ctrl: true);
    await a.click(t, find.text('Replace queue'), 'Replace mode');
    await i.enter(
      t,
      i.field('File, folder, playlist, URL, or ssh:// path'),
      '$music/list.m3u',
    );
    await a.click(t, find.text('Continue'), 'Import M3U');
    await a.click(t, find.text('Cancel'), 'Cancel replace confirmation');
    await i.loadSources(t, '$music/relative.pls', replace: true);
    expect((await a.backend.snapshot())['total'], 1);
    await i.loadSources(t, '$music/list.m3u', replace: true);
    expect((await a.backend.snapshot())['total'], 2);
    await a.click(t, find.byTooltip('Clear queue'), 'Clear queue');
    await a.click(t, find.text('Cancel'), 'Cancel clearing');
    await a.click(t, find.byTooltip('Clear queue'), 'Clear queue');
    await a.click(t, find.text('Clear'), 'Confirm clearing');
    expect((await a.backend.snapshot())['total'] ?? 0, 0);
    await a.click(t, find.byTooltip('Undo last queue edit'), 'Undo clear');
    expect((await a.backend.snapshot())['total'], 2);
  });
  await a.stage(t, 'corrupt-file-playback-error', () async {
    await i.loadSources(t, '$music/broken.wav');
    await a.click(t, find.byTooltip('Play broken'), 'Play corrupt WAV');
    await a.tick(t, 1000);
    final state = await a.backend.snapshot();
    expect(state['state'], isNot('playing'));
    await a.capture('corrupt-file-error');
    expect(await File('$music/broken.wav').exists(), isTrue);
    await a.click(
      t,
      find.byTooltip(RegExp(r'^Play (Aurora - )?Blue Hour$')),
      'Recover with valid audio',
    );
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause valid audio');
  });
  await a.stage(t, 'read-only-source-preserved', () async {
    final original = File('$music/Aurora - Blue Hour.wav');
    final destination = File('${a.root}/profile/Read only.wav');
    if (await destination.exists()) await destination.delete();
    final readonly = await original.copy(destination.path);
    final chmod = await Process.run('chmod', ['444', readonly.path]);
    expect(chmod.exitCode, 0);
    await i.loadSources(t, readonly.path);
    await a.click(t, find.byTooltip('Play Read only'), 'Play read-only audio');
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause read-only audio');
    expect(await readonly.readAsBytes(), await original.readAsBytes());
  });
  await a.stage(t, 'large-queue-pagination-range-and-scroll', () async {
    await a.nav(t, 'Queue');
    await i.loadSources(t, '${a.root}/profile/large-library', replace: true);
    expect((await a.backend.snapshot())['total'], 205);
    await a.click(
      t,
      find.text('Load more · 200 of 205'),
      'Load remaining queue',
    );
    expect(find.textContaining('Load more ·'), findsNothing);
    await a.click(t, find.byTooltip('Select tracks'), 'Select queue range');
    final boxes = find.byType(Checkbox);
    await a.click(t, boxes.first, 'Select first row');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await a.click(t, boxes.at(3), 'Shift select four rows');
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('4 selected'), findsOneWidget);
    await a.click(
      t,
      find.byTooltip('Next track'),
      'Advance playback with selection',
    );
    await a.tick(t, 1000);
    expect(find.text('4 selected'), findsOneWidget);
    expect(find.textContaining('Load more ·'), findsNothing);
    await a.resize(t, 640, 480);
    final selectionScroll = find.byWidgetPredicate(
      (w) =>
          w is Scrollbar &&
          w.scrollbarOrientation == ScrollbarOrientation.bottom,
    );
    final scrollRect = t.getRect(selectionScroll);
    await t.dragFrom(
      Offset(scrollRect.left + 30, scrollRect.bottom - 4),
      Offset(scrollRect.width - 60, 0),
    );
    await a.tick(t);
    expect(find.byTooltip('Finish selecting').hitTestable(), findsOneWidget);
    await a.click(
      t,
      find.byTooltip('Finish selecting'),
      'Reach selection end at minimum width',
    );
    await a.resize(t, 1280, 940);
    await i.enter(t, i.hint('Search your music…'), 'Audit 204');
    final exactTitle = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == 'Audit 204',
    );
    expect(exactTitle, findsOneWidget);
    final matchedRows = find
        .ancestor(of: exactTitle, matching: find.byType(ListView))
        .first;
    final titles = t
        .widgetList<Text>(
          find.descendant(of: matchedRows, matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .where((text) => text?.startsWith('Audit ') ?? false);
    expect(
      titles.first,
      'Audit 204',
      reason: 'Fuzzy search ranks the exact title first',
    );
    expect(find.textContaining('Load more ·'), findsNothing);
    await a.click(
      t,
      find.byTooltip('Clear search'),
      'Clear large queue search',
    );
  });
  await a.stage(t, 'large-saved-playlist-native-pagination', () async {
    if (find.byTooltip('Pause').evaluate().isNotEmpty) {
      await a.click(t, find.byTooltip('Pause'), 'Pause pagination fixture');
    }
    await a.click(
      t,
      find.byTooltip('Save queue as playlist'),
      'Save large queue',
    );
    await i.enter(t, i.field('Playlist name'), 'Audit large');
    await a.click(t, find.text('Save'), 'Save pagination playlist');
    await a.nav(t, 'Playlists');
    await a.click(t, find.text('Audit large'), 'Open large saved playlist');
    await a.click(
      t,
      find.byTooltip('Playlist tools: files, directories, sorting and undo'),
      'Open large playlist tools',
    );
    await a.waitFor(t, find.text('1–200 of 205'));
    await a.click(t, find.byTooltip('Next page'), 'Next saved playlist page');
    await a.waitFor(t, find.text('201–205 of 205'));
    expect(find.text('Audit 204'), findsOneWidget);
    await a.click(
      t,
      find.byTooltip('Previous page'),
      'Previous saved playlist page',
    );
    await a.waitFor(t, find.text('1–200 of 205'));
    await a.click(t, find.text('Done'), 'Close paginated playlist tools');
  });
  await a.nav(t, 'Queue');
  await i.loadSources(t, '$music/list.m3u', replace: true);
}
