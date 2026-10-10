import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await a.stage(t, 'save-queue-playlist', () async {
    await a.click(t, find.byTooltip('Save queue as playlist'), 'Save queue');
    await i.enter(t, i.field('Playlist name'), 'Audit Café 春');
    await a.click(t, find.text('Save'), 'Save playlist');
    await a.nav(t, 'Playlists');
    await a.waitFor(t, find.text('Audit Café 春'));
    await a.click(t, find.text('Audit Café 春'), 'Open saved playlist');
    expect(find.byTooltip('Track actions'), findsNWidgets(2));
    await a.click(
      t,
      find.byTooltip('Playlist tools: files, directories, sorting and undo'),
      'Playlist tools',
    );
    await a.waitFor(t, find.text('Sort and save'));
    await a.dialogSizes(t, 'playlist-tools');
    for (final sort in [
      'Track number',
      'Title',
      'Artist',
      'Album',
      'Artist + album',
      'Path',
    ]) {
      await i.choose(
        t,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButton<String>),
        ),
        sort,
      );
      await a.click(t, find.text('Sort and save'), 'Sort by $sort');
    }
    await a.click(
      t,
      find.byTooltip('Move track down').first,
      'Move playlist track down',
    );
    await a.click(
      t,
      find.byTooltip('Move track up').last,
      'Move playlist track up',
    );
    await a.click(
      t,
      find.text('Undo last playlist edit'),
      'Undo playlist edit',
    );
    await a.click(
      t,
      find.widgetWithText(TextButton, 'Refresh'),
      'Refresh playlist tools',
    );
    await a.click(t, find.text('Add files'), 'Add playlist files');
    await chooseNativePath(
      t,
      '${a.root}/profile/home/Music/Aurora - Blue Hour.wav',
    );
    await a.tick(t, 1000);
    await a.click(t, find.text('Add folder'), 'Add playlist directory');
    await chooseNativePath(t, '${a.root}/profile/home/Music');
    await a.waitFor(t, find.byTooltip('Remove directory source'));
    await a.dialogSizes(t, 'playlist-tools-directory');
    for (var n = 0; n < 2; n++) {
      await a.click(t, find.byType(Switch), 'Toggle directory recursion');
    }
    await a.click(
      t,
      find.byTooltip('Remove directory source'),
      'Remove source',
    );
    await a.click(t, find.text('Cancel'), 'Cancel source removal');
    await a.click(
      t,
      find.byTooltip('Remove directory source'),
      'Remove source',
    );
    await a.click(t, find.text('Remove source'), 'Confirm source removal');
    await a.waitFor(
      t,
      find.text('No directory sources. Added folders rescan on load.'),
    );
    await a.click(t, find.text('Done'), 'Done playlist tools');
  });
  await a.stage(t, 'playlist-create-rename-delete-undo', () async {
    await a.nav(t, 'Playlists');
    await a.click(t, find.text('New playlist'), 'New playlist');
    await i.enter(t, i.field('Playlist name'), 'Audit temporary');
    await a.click(t, find.text('Create'), 'Create playlist');
    await a.waitFor(t, find.text('Audit temporary'));
    Future<void> action(String label, String action) async {
      final tile = find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first;
      await a.click(
        t,
        find.descendant(of: tile, matching: find.byTooltip('Playlist actions')),
        'Playlist menu',
      );
      await a.click(
        t,
        find.widgetWithText(PopupMenuItem<String>, action),
        action,
      );
    }

    await action('Audit temporary', 'Rename…');
    await i.enter(t, i.field('Playlist name'), 'Renamed Café 春');
    await a.click(t, find.text('Save'), 'Save renamed playlist');
    await a.waitFor(t, find.text('Renamed Café 春'));
    await action('Renamed Café 春', 'Delete…');
    await a.click(t, find.text('Cancel'), 'Cancel delete');
    await action('Renamed Café 春', 'Delete…');
    await a.click(t, find.text('Delete'), 'Confirm delete');
    expect(find.text('Renamed Café 春'), findsNothing);
    await a.click(
      t,
      find.byTooltip('Undo last playlist edit'),
      'Undo deleted playlist',
    );
    await a.waitFor(t, find.text('Renamed Café 春'));
    await action('Audit Café 春', 'Load playlist');
    await a.waitFor(t, find.text('Your queue'));
  });
  await batches(t);
  if (Platform.environment['CLIAMP_AUDIT_PHASE'] == 'library') return;
  await visualizer(t);
  await plugins(t);
}

Future<void> visualizer(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
  for (
    var n = 0;
    n < 3 && (await a.backend.snapshot())['repeat'] != 'One';
    n++
  ) {
    final repeat = (await a.backend.snapshot())['repeat'];
    await a.click(
      t,
      find.byTooltip('Repeat: $repeat'),
      'Repeat visualization fixture',
    );
  }
  if (find.byTooltip('Pause').evaluate().isEmpty) {
    await a.click(
      t,
      find.byTooltip(RegExp(r'^Play (Aurora - )?Blue Hour$')),
      'Play visualizer fixture',
    );
  }
  expect((await a.backend.snapshot())['state'], 'playing');
  await a.stage(t, 'visualizer-all-modes-and-themes', () async {
    await a.nav(t, 'Visualizer');
    final modes = find.byType(DropdownButtonFormField<int>);
    await a.waitFor(t, modes);
    await a.tick(t, 1000);
    final options = t
        .widget<DropdownButton<int>>(
          find.descendant(
            of: modes,
            matching: find.byType(DropdownButton<int>),
          ),
        )
        .items!
        .map((e) => (e.child as Text).data!)
        .toList();
    for (final mode in options) {
      await i.choose(t, modes, mode);
      await a.tick(t, 150);
      expect((await a.backend.snapshot())['visualizer'], mode);
      a.results.add({'stage': a.current, 'visualizerSelected': mode});
    }
    final themes = find.byType(DropdownButtonFormField<String>);
    final names = t
        .widget<DropdownButton<String>>(
          find.descendant(
            of: themes,
            matching: find.byType(DropdownButton<String>),
          ),
        )
        .items!
        .map((e) => (e.child as Text).data!)
        .toList();
    for (final theme in names) {
      await i.choose(t, themes, theme);
      await a.tick(t, 900);
      expect(((await a.backend.snapshot())['theme'] as Map)['name'], theme);
      final caption = find.text(
        'Original Cliamp visualizers, including your Lua extensions.',
      );
      final palette = Theme.of(t.element(caption));
      if (palette.brightness == Brightness.light) {
        await a.capture('visualizer-light-${theme.replaceAll(' ', '-')}');
        final foreground = t.widget<Text>(caption).style!.color!;
        final first = foreground.computeLuminance();
        final second = palette.scaffoldBackgroundColor.computeLuminance();
        final ratio = first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
        a.results.add({
          'stage': a.current,
          'lightTheme': theme,
          'captionContrast': ratio,
        });
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'Visualizer caption must remain readable in $theme',
        );
      }
    }
    await a.click(t, find.text('Cancel preview'), 'Restore appearance');
    await a.click(t, find.byTooltip('Next visualizer'), 'Next visualizer');
    await a.click(t, find.text('Apply appearance'), 'Apply appearance');
    await a.click(
      t,
      find.byTooltip('Enter fullscreen visualizer'),
      'Fullscreen',
    );
    await a.dialogSizes(t, 'fullscreen-visualizer');
    await a.click(t, find.byTooltip('Next visualizer').last, 'Fullscreen next');
    for (final control in [
      'Previous track (,)',
      'Next track (.)',
      'Lower volume (-)',
      'Raise volume (+)',
      'Seek back 5 seconds (Left)',
      'Seek forward 5 seconds (Right)',
    ]) {
      await a.click(t, find.byTooltip(control), control);
    }
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.comma,
      LogicalKeyboardKey.period,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyV,
    ]) {
      await a.key(t, key);
    }
    await a.key(t, LogicalKeyboardKey.escape);
    expect(find.byTooltip('Enter fullscreen visualizer'), findsOneWidget);
  });
}

Future<void> plugins(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
  if (find.byTooltip('Pause').evaluate().isEmpty) {
    await a.click(
      t,
      find.byTooltip(RegExp(r'^Play (Aurora - )?Blue Hour$')),
      'Play before restart',
    );
  }
  await a.waitFor(t, find.byTooltip('Pause'));
  await a.click(t, find.byTooltip('Pause'), 'Pause before restart');
  await a.key(t, LogicalKeyboardKey.keyJ, ctrl: true);
  await i.enter(t, i.field('Time'), '0:45');
  await a.click(t, find.text('Jump'), 'Set restart resume position');
  await i.menu(t, 'Track actions', 'Play next', index: 1);
  await a.nav(t, 'Plugins');
  await a.stage(t, 'plugin-invalid-source', () async {
    await a.click(t, find.text('Manage plugins'), 'Manage plugins');
    await i.enter(t, i.field('Plugin source'), 'not a valid plugin ! 春');
    await a.click(t, find.text('Review source'), 'Review invalid source');
    await a.tick(t, 1000);
    await a.capture('plugin-invalid-source');
    await a.click(t, find.text('Done'), 'Done plugin manager');
  });
  // A harmless local fixture is reviewed using the same UI as real plugins.
  final path = '${a.profilePath}/config/cliamp';
  const code =
      'local count=0\nlocal p=plugin.register({name="Audit",type="hook",permissions={"keymap"}})\np:command("ping",function(args) return "Audit OK "..count end)\np:bind("ctrl+n","Audit counter",function() count=count+1 end)\n';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.write(code);
    await request.response.close();
  });
  try {
    await a.stage(t, 'plugin-install-local-http-fixture', () async {
      await a.click(t, find.text('Manage plugins'), 'Manage plugins');
      await i.enter(
        t,
        i.field('Plugin source'),
        'http://127.0.0.1:${server.port}/audit.lua',
      );
      await a.click(t, find.text('Review source'), 'Review fixture source');
      await a.waitFor(t, find.textContaining('I approve this exact source'));
      expect(find.textContaining('local count=0'), findsOneWidget);
      await a.click(
        t,
        find.byType(CheckboxListTile),
        'Approve known audit fixture',
      );
      await a.click(t, find.text('Trust and install'), 'Install audit fixture');
      final beforeRestart = await a.backend.call('queue.list');
      final beforeNext = await a.backend.call('playnext.list');
      final beforeState = await a.backend.snapshot();
      await a.click(t, find.text('Restart player'), 'Restart after install');
      final afterRestart = await a.backend.call('queue.list');
      expect(
        afterRestart['tracks'],
        beforeRestart['tracks'],
        reason: 'Restart must preserve the queue',
      );
      expect(
        (await a.backend.call('playnext.list'))['tracks'],
        beforeNext['tracks'],
      );
      final afterState = await a.backend.snapshot();
      expect(afterState['state'], 'paused');
      expect(
        afterState['position'] ?? 0,
        closeTo((beforeState['position'] as num?)?.toDouble() ?? 0, .2),
      );
      expect(afterState['repeat'], beforeState['repeat']);
      await a.nav(t, 'Plugins');
      await a.waitFor(t, find.text('Audit ping'));
      await a.click(t, find.text('Audit counter'), 'Run plugin key binding');
      await a.key(t, LogicalKeyboardKey.keyN, ctrl: true);
      await a.click(
        t,
        find.text('Audit ping'),
        'Run registered plugin command',
      );
      await a.click(t, find.text('Continue'), 'Plugin name');
      await a.click(t, find.text('Continue'), 'Plugin subcommand');
      await a.click(t, find.text('Run'), 'Run ping');
      await a.waitFor(t, find.text('Audit OK 2'));
      await a.click(t, find.text('Close'), 'Close command output');
    });
  } finally {
    await server.close(force: true);
  }
  await a.stage(t, 'plugin-review-configure-toggle-remove', () async {
    await a.click(t, find.text('Manage plugins'), 'Manage plugins');
    await a.waitFor(t, find.text('Audit'));
    Future<void> action(String item) async {
      await a.click(
        t,
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
        'Plugin actions',
      );
      await a.click(t, find.widgetWithText(PopupMenuItem<String>, item), item);
    }

    await action('Review and trust content');
    await a.waitFor(t, find.textContaining('I approve this exact source'));
    await a.dialogSizes(t, 'plugin-review');
    await a.click(t, find.text('Cancel'), 'Cancel plugin approval');
    await action('Review and trust content');
    await a.click(t, find.byType(CheckboxListTile), 'Approve harmless fixture');
    await a.click(t, find.text('Trust this content'), 'Trust fixture content');
    await a.tick(t, 700);
    await action('Disable');
    await action('Enable');
    await action('Plugin settings');
    await i.enter(t, i.field('Setting name'), 'audit_note');
    await i.enter(t, i.field('New value or environment reference'), 'Café 春');
    await a.click(t, find.text('Add change'), 'Add plugin setting');
    await a.click(t, find.text('Save settings'), 'Save plugin settings');
    await action('Remove');
    await a.click(t, find.text('Cancel'), 'Cancel plugin removal');
    await action('Remove');
    await a.click(
      t,
      find.widgetWithText(FilledButton, 'Remove'),
      'Confirm plugin removal',
    );
    await a.click(t, find.text('Done'), 'Done plugin manager');
    expect(await File('$path/plugins/audit.lua').exists(), isFalse);
  });
}

Future<String> nativePicker(WidgetTester t) async {
  for (var n = 0; n < 50; n++) {
    final tree = await Process.run('xwininfo', ['-root', '-tree']);
    final matches = RegExp(
      r'(0x[0-9a-f]+) "([^"]+)"',
    ).allMatches('${tree.stdout}');
    for (final match in matches) {
      final name = match.group(2)!.toLowerCase();
      if (name.contains('open') ||
          name.contains('select') ||
          name.contains('choose')) {
        return match.group(1)!;
      }
    }
    await a.tick(t, 100);
  }
  throw StateError('Native file chooser did not open');
}

Future<void> nativeKeys(String window, List<String> keys) async {
  final result = await Process.run('python3', [
    '${a.root}/window.py',
    'key',
    window,
    ...keys,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Future<void> pickerHome(WidgetTester t, String window) async {
  final info = await Process.run('xwininfo', ['-id', window]);
  expect(info.exitCode, 0);
  int number(String label) => int.parse(
    RegExp('$label:\\s+(-?[0-9]+)').firstMatch('${info.stdout}')!.group(1)!,
  );
  // GTK's empty Recent view cannot resolve folder selections from its location
  // entry. Start from Home, just as a user navigating the sidebar would.
  await Process.run('python3', [
    '${a.root}/window.py',
    'click',
    window,
    '${number('Absolute upper-left X') + 55}',
    '${number('Absolute upper-left Y') + 59}',
  ]);
  await a.tick(t, 700);
}

Future<void> chooseNativePath(WidgetTester t, String path) async {
  final window = await nativePicker(t);
  await Process.run('import', [
    '-window',
    window,
    '${a.root}/evidence/${a.current}-chooser.png',
  ]);
  await pickerHome(t, window);
  await nativeKeys(window, ['Control_L', 'l']);
  await a.tick(t, 350);
  await a.tick(t, 100);
  final typed = await Process.run('python3', [
    '${a.root}/window.py',
    'type',
    window,
    path,
  ]);
  expect(typed.exitCode, 0);
  await a.tick(t, 100);
  await nativeKeys(window, ['Return']);
  await a.tick(t, 700);
  if (await Directory(path).exists()) {
    final info = await Process.run('xwininfo', ['-id', window]);
    if (info.exitCode == 0) {
      await nativeKeys(window, ['Return']);
      await a.tick(t, 1000);
    }
  }
}

Future<void> multiFilePicker(WidgetTester t) async {
  final directory = await Directory(
    '${a.root}/profile/multi-select',
  ).create(recursive: true);
  for (final name in ['First.wav', 'Second.wav']) {
    await File(
      '${a.root}/profile/home/Music/Aurora - Blue Hour.wav',
    ).copy('${directory.path}/$name');
  }
  await a.stage(t, 'native-multiple-file-selection', () async {
    final before = (await a.backend.snapshot())['total'] as int? ?? 0;
    await a.key(t, LogicalKeyboardKey.keyO, ctrl: true);
    await a.click(t, find.text('Choose files'), 'Choose multiple files');
    final window = await nativePicker(t);
    await pickerHome(t, window);
    await nativeKeys(window, ['Control_L', 'l']);
    await a.tick(t, 350);
    await Process.run('python3', [
      '${a.root}/window.py',
      'type',
      window,
      '${directory.path}/',
    ]);
    await nativeKeys(window, ['Return']);
    await a.tick(t, 1000);
    final info = await Process.run('xwininfo', ['-id', window]);
    expect(info.exitCode, 0);
    int number(String label) => int.parse(
      RegExp('$label:\\s+(-?[0-9]+)').firstMatch('${info.stdout}')!.group(1)!,
    );
    await Process.run('import', [
      '-window',
      window,
      '${a.root}/evidence/multiple-file-location.png',
    ]);
    await Process.run('python3', [
      '${a.root}/window.py',
      'click',
      window,
      '${number('Absolute upper-left X') + (number('Width') * .6).round()}',
      '${number('Absolute upper-left Y') + (number('Height') * .4).round()}',
    ]);
    await nativeKeys(window, ['Control_L', 'a']);
    await a.tick(t, 300);
    await Process.run('import', [
      '-window',
      window,
      '${a.root}/evidence/multiple-file-selected.png',
    ]);
    await nativeKeys(window, ['Alt_L', 'o']);
    await a.tick(t, 1500);
    expect(find.text('Add your music'), findsNothing);
    final tracks = (await a.backend.call('queue.list'))['tracks'] as List;
    expect((await a.backend.snapshot())['total'], before + 2);
    expect(
      tracks.skip(tracks.length - 2).map((track) => track['path']).toSet(),
      {'${directory.path}/First.wav', '${directory.path}/Second.wav'},
    );
  });
}

Future<void> fileDialogs(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await multiFilePicker(t);
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
  for (final folder in [false, true]) {
    for (final cancel in [true, false]) {
      await a.stage(
        t,
        'native-${folder ? 'folder' : 'file'}-picker-${cancel ? 'cancel' : 'select'}',
        () async {
          await a.key(t, LogicalKeyboardKey.keyO, ctrl: true);
          await a.click(
            t,
            find.text(folder ? 'Choose folders' : 'Choose files'),
            'Open native picker',
          );
          if (cancel) {
            await nativeKeys(await nativePicker(t), ['Escape']);
            await a.tick(t, 500);
            await a.click(t, find.text('Cancel'), 'Cancel import');
          } else {
            final path =
                '${a.root}/profile/home/Music${folder ? '' : '/Aurora - Blue Hour.wav'}';
            await chooseNativePath(t, path);
            await a.waitFor(t, find.text('Your queue'));
            expect(find.text('Add your music'), findsNothing);
            await a.tick(t, 1500);
            expect((await a.backend.snapshot())['total'], greaterThan(2));
            final queue =
                (await a.backend.call('queue.list'))['tracks'] as List;
            expect(queue.last['path'], startsWith(folder ? '$path/' : path));
          }
        },
      );
    }
  }
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
}

Future<void> batches(WidgetTester t) async {
  await a.nav(t, 'Queue');
  // The null audio sink consumes the fixture faster than wall-clock playback.
  // Keep replacement playback alive until the test explicitly pauses it;
  // otherwise enqueue legitimately starts a stopped player and drains play-next.
  for (
    var n = 0;
    n < 3 && (await a.backend.snapshot())['repeat'] != 'One';
    n++
  ) {
    final repeat = (await a.backend.snapshot())['repeat'];
    await a.click(t, find.byTooltip('Repeat: $repeat'), 'Repeat batch fixture');
  }

  Future<void> select() async {
    if (find.byTooltip('Finish selecting').evaluate().isEmpty) {
      await a.click(t, find.byTooltip('Select tracks'), 'Select tracks');
    }
    await a.click(t, find.text('Select visible'), 'Select all visible');
  }

  await a.stage(t, 'batch-append-remove-replace-undo', () async {
    await select();
    await a.click(t, find.text('Append'), 'Batch append');
    expect((await a.backend.snapshot())['total'], 4);
    await a.click(t, find.byTooltip('Undo last queue edit'), 'Undo append');
    expect((await a.backend.snapshot())['total'], 2);
    await a.click(t, find.byTooltip('Finish selecting'), 'Finish selection');
    await select();
    await a.click(t, find.text('Remove'), 'Batch remove');
    await a.click(
      t,
      find.widgetWithText(FilledButton, 'Remove'),
      'Confirm batch remove',
    );
    expect((await a.backend.snapshot())['total'] ?? 0, 0);
    await a.click(
      t,
      find.byTooltip('Undo last queue edit'),
      'Undo batch remove',
    );
    expect((await a.backend.snapshot())['total'], 2);
    await a.click(t, find.byTooltip('Finish selecting'), 'Finish selection');
    await select();
    await a.click(t, find.text('Replace queue'), 'Batch replace');
    await a.click(t, find.text('Cancel'), 'Cancel batch replace');
    await a.click(t, find.text('Replace queue'), 'Batch replace');
    await a.click(t, find.text('Replace'), 'Confirm batch replace');
    expect((await a.backend.snapshot())['total'], 2);
    await a.click(t, find.byTooltip('Finish selecting'), 'Finish selection');
  });
  if (find.byTooltip('Pause').evaluate().isNotEmpty) {
    await a.click(t, find.byTooltip('Pause'), 'Pause after batch replacement');
  }
  await a.stage(t, 'batch-save-and-prepend-destination', () async {
    await select();
    await a.click(t, find.text('Save to playlist'), 'Save selected');
    await a.dialogSizes(t, 'save-to-playlist');
    await a.click(t, find.text('Place at the beginning'), 'Prepend selection');
    await a.click(t, find.text('New playlist'), 'New destination');
    await i.enter(t, i.field('Playlist name'), 'Audit selection');
    await a.click(t, find.text('Create'), 'Create selection playlist');
    await a.click(t, find.byTooltip('Finish selecting'), 'Finish selection');
    await i.menu(t, 'Track actions', 'Add to playlist…');
    await a.click(t, find.text('Place at the beginning'), 'Prepend one track');
    await a.click(t, find.text('Audit selection'), 'Existing destination');
    final saved = await a.backend.call('provider.tracks', {
      'provider': 'local',
      'playlist': 'Audit selection',
    });
    expect(saved['total'], 2);
  });
  await a.stage(t, 'play-next-batch-move-and-clear', () async {
    await select();
    await a.click(
      t,
      find.widgetWithText(TextButton, 'Play next'),
      'Queue selected next',
    );
    await a.nav(t, 'Play next');
    await a.waitFor(t, find.byTooltip('Track actions'));
    expect(find.byTooltip('Track actions'), findsNWidgets(2));
    await i.menu(t, 'Track actions', 'Move down');
    await i.menu(t, 'Track actions', 'Move up', index: 1);
    await a.click(t, find.byTooltip('Clear play next'), 'Clear play next');
    await a.click(t, find.text('Cancel'), 'Cancel clearing next');
    await a.click(t, find.byTooltip('Clear play next'), 'Clear play next');
    await a.click(t, find.text('Clear'), 'Confirm clearing next');
    expect(find.byTooltip('Track actions'), findsNothing);
    await a.nav(t, 'Queue');
  });
}
