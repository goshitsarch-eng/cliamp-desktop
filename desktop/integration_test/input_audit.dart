import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Playlists');
  await a.stage(t, 'empty-playlist-name-validation', () async {
    await a.click(t, find.text('New playlist'), 'New playlist');
    await i.enter(t, i.field('Playlist name'), '   ');
    await a.click(t, find.text('Create'), 'Reject blank playlist name');
    expect(find.text('Enter a playlist name.'), findsOneWidget);
    await a.click(t, find.text('Cancel'), 'Cancel blank playlist');
  });
  await a.stage(t, 'playlist-long-duplicate-and-invalid-names', () async {
    final name = 'Long playlist ${'title ' * 25}'.trim();
    await a.click(t, find.text('New playlist'), 'New long playlist');
    await i.enter(t, i.field('Playlist name'), name);
    await a.click(t, find.text('Create'), 'Create long name');
    await a.waitFor(t, find.text(name));
    await a.click(t, find.text('New playlist'), 'Create duplicate');
    await i.enter(t, i.field('Playlist name'), name);
    await a.click(t, find.text('Create'), 'Reject duplicate name');
    expect(find.byType(SnackBar), findsWidgets);
    await a.click(t, find.text(name), 'Open long-named playlist');
    await a.click(
      t,
      find.byTooltip('Playlist tools: files, directories, sorting and undo'),
      'Manage long name',
    );
    await a.dialogSizes(t, 'long-playlist-tools');
    await a.click(t, find.text('Done'), 'Close long playlist');
    await a.nav(t, 'Playlists');
    await a.click(t, find.text('New playlist'), 'New invalid playlist');
    await i.enter(t, i.field('Playlist name'), '../escape');
    await a.click(t, find.text('Create'), 'Reject path traversal name');
    expect(find.byType(SnackBar), findsWidgets);
    expect(find.text('../escape'), findsNothing);
  });
  await a.nav(t, 'Plugins');
  await a.stage(t, 'empty-plugin-source-validation', () async {
    await a.click(t, find.text('Manage plugins'), 'Manage plugins');
    await a.click(t, find.text('Review source'), 'Reject blank plugin source');
    expect(find.text('Enter a plugin source to review.'), findsOneWidget);
    await a.click(t, find.text('Done'), 'Close empty plugin review');
  });
}
