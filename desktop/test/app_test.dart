import 'dart:async';

import 'package:cliamp_desktop/src/app.dart';
import 'package:cliamp_desktop/src/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Json = Map<String, dynamic>;
typedef _Call = ({String operation, _Json params});

class _FakeBackend implements PlayerBackend {
  final _events = StreamController<_Json>.broadcast();
  final _spectrum = StreamController<List<double>>.broadcast();
  final calls = <_Call>[];
  final failures = <String, BackendException>{};
  int failedConnections = 0;
  int connections = 0;
  bool closed = false;
  _Json? listening;
  Map<String, _Json>? playlistCapabilities;
  final providers = <_Json>[
    {'key': 'local', 'name': 'Local library'},
  ];
  final playlists = <_Json>[
    {'id': 'mix-17', 'name': 'Study mix', 'track_count': 2},
  ];
  _Json? deletedPlaylist;
  Completer<_Json>? pendingQueue;
  final tracks = <_Json>[
    {
      'title': 'Night Drive',
      'artist': 'The Test Ensemble',
      'album': 'After Hours',
      'path': '/music/night drive.flac',
      'duration_secs': 240,
      'index': 0,
    },
    {
      'title': 'Morning Light',
      'artist': 'The Test Ensemble',
      'album': 'Daybreak',
      'path': '/music/morning.flac',
      'duration_secs': 180,
      'index': 1,
    },
  ];
  late _Json state = {
    'revision': 7,
    'playlist_revision': 41,
    'state': 'paused',
    'track': tracks.first,
    'index': 0,
    'total': tracks.length,
    'position': 15.0,
    'duration': 240.0,
    'seekable': true,
    'volume': -12.0,
    'eq_preset': 'Flat',
    'eq_bands': List<double>.filled(10, 0),
    'shuffle': false,
    'repeat': 'off',
    'mono': false,
    'speed': 1.0,
  };

  @override
  Future<void> connect() async {
    connections++;
    if (failedConnections > 0) {
      failedConnections--;
      throw const BackendException('Smoke engine unavailable.');
    }
  }

  @override
  Future<_Json> snapshot() async => Map.of(state);

  @override
  Future<_Json> capabilities() async => {
    'operations': [
      for (final name in [
        'queue.play',
        'queue.remove',
        'queue.enqueue',
        'queue.remove_many',
        'queue.undo',
        'toggle',
        'volume',
        'eq',
        'provider.playlists',
        'provider.tracks',
        'provider.search',
        if (listening != null) 'provider.playback_state',
        if (playlistCapabilities != null) ...[
          'playlist.capabilities',
          'playlist.create',
          'playlist.rename',
          'playlist.delete',
          'playlist.undo',
        ],
        'plugin.commands',
        'plugin.call',
        'desktop.vis',
        'desktop.theme',
        'desktop.vis.frame',
      ])
        {'name': name, 'description': name},
    ],
  };

  @override
  Future<_Json> call(String operation, [_Json params = const {}]) async {
    calls.add((operation: operation, params: Map.of(params)));
    final failure = failures[operation];
    if (failure != null) throw failure;
    switch (operation) {
      case 'provider.list':
        return {'ok': true, 'providers': providers};
      case 'playlist.capabilities':
        return {'ok': true, ...?playlistCapabilities?[params['provider']]};
      case 'queue.list':
        if (pendingQueue != null) return pendingQueue!.future;
        return {'ok': true, 'tracks': List.of(tracks), 'total': tracks.length};
      case 'provider.tracks':
      case 'provider.search':
        return {'ok': true, 'tracks': List.of(tracks), 'total': tracks.length};
      case 'provider.playback_state':
        return {'ok': true, 'listening': listening ?? <String, dynamic>{}};
      case 'playnext.list':
        return {'ok': true, 'tracks': <_Json>[], 'total': 0};
      case 'provider.playlists':
        return {
          'ok': true,
          'playlists': List.of(playlists),
          'total': playlists.length,
        };
      case 'playlist.delete':
        deletedPlaylist = playlists.firstWhere(
          (playlist) => playlist['id'] == params['playlist'],
        );
        playlists.remove(deletedPlaylist);
      case 'playlist.undo':
        if (deletedPlaylist != null &&
            deletedPlaylist!['id'] == params['playlist']) {
          playlists.add(deletedPlaylist!);
          deletedPlaylist = null;
        }
      case 'history':
        return {
          'ok': true,
          'history': [
            {'track': tracks.last, 'played_at': '2026-10-09T12:00:00Z'},
          ],
          'total': 1,
        };
      case 'lyrics':
        return {
          'ok': true,
          'lyrics': [
            {'start': 0.0, 'text': 'A quiet opening'},
            {'start': 20.0, 'text': 'The chorus comes around'},
          ],
        };
      case 'device':
        return {
          'ok': true,
          'devices': [
            {'name': 'System speakers', 'active': true},
          ],
        };
      case 'plugin.commands':
        return {
          'ok': true,
          'items': ['sleep timer'],
        };
      case 'desktop.vis':
        return {
          'ok': true,
          'items': ['Bars', 'Wave'],
          'index': 0,
          'visualizer': 'Bars',
        };
      case 'desktop.theme':
        return {
          'ok': true,
          'items': ['Default - Terminal colors'],
        };
      case 'desktop.vis.frame':
        return {
          'ok': true,
          'frame': '\u001b[38;2;129;230;205m▁▂▅\u001b[0m',
          'visualizer': 'Bars',
          'index': 0,
          'theme': {'name': 'Default - Terminal colors'},
        };
      case 'toggle':
        state['state'] = state['state'] == 'playing' ? 'paused' : 'playing';
      case 'queue.play':
        state['track'] = tracks[params['index'] as int];
        state['index'] = params['index'];
        state['state'] = 'playing';
      case 'queue.remove':
        tracks.removeAt(params['index'] as int);
        state['total'] = tracks.length;
        state['playlist_revision'] = (state['playlist_revision'] as int) + 1;
      case 'queue.remove_many':
        final indexes = List<int>.from(params['indexes'] as List)
          ..sort((a, b) => b.compareTo(a));
        for (final index in indexes) {
          tracks.removeAt(index);
        }
        state['total'] = tracks.length;
        state['playlist_revision'] = (state['playlist_revision'] as int) + 1;
      case 'volume':
        state['volume'] = params['value'];
      case 'seek.absolute':
        state['position'] = params['value'];
    }
    return {'ok': true};
  }

  void publishState(_Json changes) {
    state = {...state, ...changes};
    _events.add({'event': 'runtime.state', 'data': Map.of(state)});
  }

  void interruptConnection() => _events.addError(
    const BackendException('Engine connection interrupted.'),
  );

  List<_Call> mutations(String operation) =>
      calls.where((call) => call.operation == operation).toList();

  @override
  Stream<_Json> get events => _events.stream;
  @override
  Stream<List<double>> get spectrum => _spectrum.stream;
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _events.close();
    await _spectrum.close();
  }
}

Future<void> _open(
  WidgetTester tester,
  _FakeBackend backend, {
  Size size = const Size(1300, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(backend.close);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(CliampApp(backend: backend));
  await tester.pumpAndSettle();
}

Future<void> _navigate(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shared engine theme events recolor the desktop and reset to default',
    (tester) async {
      final backend = _FakeBackend();
      await _open(tester, backend);
      ThemeData currentTheme() =>
          Theme.of(tester.element(find.byType(Scaffold).first));
      expect(currentTheme().brightness, Brightness.dark);
      backend.publishState({
        'theme': {
          'name': 'Light fixture',
          'bg': '#eff1f5',
          'accent': '#8839ef',
          'fg': '#6c6f85',
          'bright_fg': '#4c4f69',
        },
      });
      await tester.pumpAndSettle();
      expect(currentTheme().brightness, Brightness.light);
      expect(currentTheme().scaffoldBackgroundColor, const Color(0xffeff1f5));
      expect(currentTheme().colorScheme.primary, const Color(0xff8839ef));
      backend.publishState({
        'theme': {'name': 'default'},
      });
      await tester.pumpAndSettle();
      expect(currentTheme().brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fuzzy filtering keeps the original engine row index', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    await tester.enterText(find.byType(TextField).first, 'mrlgt');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play Morning Light'), findsOneWidget);
    expect(find.byTooltip('Play Night Drive'), findsNothing);
    await tester.tap(find.byTooltip('Play Morning Light'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(backend.mutations('queue.play').single.params, {
      'index': 1,
      'if_revision': 41,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multi-selection removes one atomic batch with its displayed revision',
    (tester) async {
      final backend = _FakeBackend();
      await _open(tester, backend);
      await tester.tap(find.byTooltip('Select tracks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select visible'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Remove'));
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove 2 tracks?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      final call = backend.mutations('queue.remove_many').single;
      expect(call.params['indexes'], [0, 1]);
      expect(call.params['if_revision'], 41);
      expect((call.params['tracks'] as List).map((track) => track['path']), [
        '/music/night drive.flac',
        '/music/morning.flac',
      ]);
      expect(backend.mutations('queue.remove'), isEmpty);
      expect(backend.tracks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typing and editing in search never invokes playback shortcuts', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'morning');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    for (final operation in ['toggle', 'prev', 'seek', 'queue.undo']) {
      expect(
        backend.mutations(operation),
        isEmpty,
        reason: '$operation interrupted text entry',
      );
    }
    // Playback remains keyboard-accessible after leaving the text field.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(backend.mutations('toggle'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes a track menu and preserves search and selection', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    await tester.enterText(find.byType(TextField).first, 'morning');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.byTooltip('Select tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select visible'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Track actions'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Add to playlist…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Add to playlist…'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'morning',
    );
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Select visible'), findsOneWidget);
    expect(find.byTooltip('Play Night Drive'), findsNothing);
    expect(find.byTooltip('Play Morning Light'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Jump to time seeks precisely and rejects a changed playing track',
    (tester) async {
      final backend = _FakeBackend();
      await _open(tester, backend);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final input = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(input, '1:35');
      await tester.tap(find.widgetWithText(FilledButton, 'Jump'));
      await tester.pumpAndSettle();
      expect(backend.mutations('seek.absolute').single.params, {'value': 95.0});

      await tester.tap(find.byTooltip('Jump to time'));
      await tester.pumpAndSettle();
      await tester.enterText(input, '2:00');
      backend.publishState({'track': backend.tracks.last, 'index': 1});
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Jump'));
      await tester.pumpAndSettle();
      expect(backend.mutations('seek.absolute'), hasLength(1));
      expect(
        find.text('The playing track changed. Open Jump to time again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unavailable engine offers retry and loads the queue afterward',
    (tester) async {
      final backend = _FakeBackend()..failedConnections = 1;
      await _open(tester, backend);
      expect(find.text('Smoke engine unavailable.'), findsOneWidget);
      expect(find.text('Retry connection'), findsOneWidget);
      expect(backend.mutations('queue.list'), isEmpty);

      await tester.tap(find.text('Retry connection'));
      await tester.pumpAndSettle();
      expect(backend.connections, 2);
      expect(find.text('Engine connected'), findsOneWidget);
      expect(find.text('Morning Light'), findsOneWidget);
      expect(find.text('Smoke engine unavailable.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('queue actions use the current revision from runtime events', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    await tester.tap(find.byTooltip('Play Morning Light'));
    // Track rows also support double-click; let the gesture arena resolve.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(backend.mutations('queue.play').single.params, {
      'index': 1,
      'if_revision': 41,
    });
    expect(find.byTooltip('Pause'), findsOneWidget);

    backend.publishState({'playlist_revision': 84});
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Track actions').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from list'));
    await tester.pumpAndSettle();
    expect(backend.mutations('queue.remove').single.params, {
      'index': 0,
      'if_revision': 84,
    });
    expect(find.text('Night Drive'), findsNothing);
    expect(backend.tracks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recovered runtime stream clears the offline state', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    backend.interruptConnection();
    await tester.pumpAndSettle();
    expect(find.text('Engine connection interrupted.'), findsOneWidget);
    expect(find.text('Retry connection'), findsOneWidget);

    backend.publishState({'revision': 8});
    await tester.pumpAndSettle();
    expect(find.text('Engine connection interrupted.'), findsNothing);
    expect(find.text('Engine connected'), findsOneWidget);
    expect(find.text('Morning Light'), findsOneWidget);
    expect(backend.connections, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an old visible row keeps its revision while a refresh is pending',
    (tester) async {
      final backend = _FakeBackend();
      await _open(tester, backend);
      final refreshed = Completer<_Json>();
      backend.pendingQueue = refreshed;
      backend.failures['queue.play'] = const BackendException(
        'The queue changed. Refresh and try again.',
        code: 'conflict',
      );
      backend.publishState({'playlist_revision': 84});
      await tester.pump();
      await tester.tap(find.byTooltip('Play Morning Light'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(backend.mutations('queue.play').single.params, {
        'index': 1,
        'if_revision': 41,
      });

      backend.pendingQueue = null;
      refreshed.complete({
        'ok': true,
        'tracks': List.of(backend.tracks),
        'total': backend.tracks.length,
      });
      await tester.pumpAndSettle();
      expect(
        backend.mutations('queue.play'),
        hasLength(1),
        reason: 'A conflicting play operation must never be replayed.',
      );
      expect(
        find.text('The queue changed. Refresh and try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playback errors are visible and library navigation still works',
    (tester) async {
      final backend = _FakeBackend();
      backend.failures['toggle'] = const BackendException(
        'The selected audio output is unavailable.',
      );
      await _open(tester, backend);
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(
        find.text('The selected audio output is unavailable.'),
        findsOneWidget,
      );
      expect(backend.mutations('toggle'), hasLength(1));
      expect(backend.state['state'], 'paused');

      await _navigate(tester, 'History');
      expect(backend.mutations('history'), hasLength(1));
      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Morning Light'), findsOneWidget);
      await _navigate(tester, 'Lyrics');
      expect(find.text('A quiet opening'), findsOneWidget);
      await tester.tap(find.text('The chorus comes around'));
      await tester.pumpAndSettle();
      expect(backend.mutations('seek.absolute').single.params, {'value': 20.0});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playlist loading keeps provider IDs and can retry a load error',
    (tester) async {
      final backend = _FakeBackend();
      backend.failures['provider.tracks'] = const BackendException(
        'Library permission denied.',
      );
      await _open(tester, backend);
      await _navigate(tester, 'Playlists');
      expect(find.text('Study mix'), findsOneWidget);
      await tester.tap(find.text('Study mix'));
      await tester.pumpAndSettle();
      expect(backend.mutations('provider.tracks').single.params, {
        'provider': 'local',
        'playlist': 'mix-17',
        'limit': 200,
      });
      expect(find.text('Library permission denied.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      backend.failures.remove('provider.tracks');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Library permission denied.'), findsNothing);
      expect(find.text('Morning Light'), findsOneWidget);
      expect(backend.mutations('provider.tracks'), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a deleted playlist can be undone from the list and retried after failure',
    (tester) async {
      final backend = _FakeBackend();
      backend.playlistCapabilities = {
        'local': {'delete': true, 'undo': true},
      };
      await _open(tester, backend);
      await _navigate(tester, 'Playlists');
      await tester.tap(find.byTooltip('Playlist actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete…'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Study mix?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Study mix'), findsNothing);
      expect(backend.mutations('playlist.delete').single.params, {
        'provider': 'local',
        'playlist': 'mix-17',
      });

      backend.failures['playlist.undo'] = const BackendException(
        'Playlist storage is temporarily unavailable.',
      );
      await tester.tap(find.byTooltip('Undo last playlist edit'));
      await tester.pumpAndSettle();
      expect(find.text('Study mix'), findsNothing);
      expect(find.byTooltip('Undo last playlist edit'), findsOneWidget);
      expect(
        find.text('Playlist storage is temporarily unavailable.'),
        findsOneWidget,
      );
      backend.failures.remove('playlist.undo');
      await tester.tap(find.byTooltip('Undo last playlist edit'));
      await tester.pumpAndSettle();
      expect(find.text('Study mix'), findsOneWidget);
      expect(find.byTooltip('Undo last playlist edit'), findsNothing);
      expect(backend.mutations('playlist.undo'), hasLength(2));
      for (final call in backend.mutations('playlist.undo')) {
        expect(call.params, {'provider': 'local', 'playlist': 'mix-17'});
      }
      expect(backend.state['playlist_revision'], 41);
      expect(backend.tracks, hasLength(2));
      expect(backend.mutations('queue.undo'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playlist write controls follow the selected provider capabilities',
    (tester) async {
      final backend = _FakeBackend();
      backend.providers.add({'key': 'readonly', 'name': 'Read only library'});
      backend.playlistCapabilities = {
        'local': {
          'create': true,
          'rename': true,
          'delete': true,
          'remove': true,
          'remove_many': true,
        },
        'readonly': {
          'create': false,
          'rename': false,
          'delete': false,
          'remove': false,
          'remove_many': false,
        },
      };
      await _open(tester, backend);
      await _navigate(tester, 'Playlists');
      expect(find.text('New playlist'), findsOneWidget);
      await tester.tap(find.byTooltip('Playlist actions'));
      await tester.pumpAndSettle();
      expect(find.text('Rename…'), findsOneWidget);
      expect(find.text('Delete…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read only library').last);
      await tester.pumpAndSettle();
      expect(find.text('New playlist'), findsNothing);
      await tester.tap(find.byTooltip('Playlist actions'));
      await tester.pumpAndSettle();
      expect(find.text('Load playlist'), findsOneWidget);
      expect(find.text('Rename…'), findsNothing);
      expect(find.text('Delete…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study mix'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Track actions').first);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Add to playlist…'), findsOneWidget);
      expect(find.text('Remove from list'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select tracks'));
      await tester.pumpAndSettle();
      expect(find.text('Select visible'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Remove'), findsNothing);
      expect(
        backend
            .mutations('playlist.capabilities')
            .map((call) => call.params['provider']),
        containsAll(['local', 'readonly']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('volume changes preserve the backend decibel unit', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend);
    // The other slider is the 240-second seek bar. Test the gesture rather than
    // assuming whether the UI represents dB directly or maps a normalized value.
    final volume = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.max <= 6,
    );
    expect(volume, findsOneWidget);
    await tester.drag(volume, const Offset(-20, 0));
    await tester.pumpAndSettle();
    final value = backend.mutations('volume').last.params['value'] as num;
    expect(value, lessThan(-12), reason: 'Dragging left should lower -12 dB.');
    expect(value, greaterThanOrEqualTo(-90));
    expect(tester.takeException(), isNull);
  });

  testWidgets('library rows show provider listening and resume markers', (
    tester,
  ) async {
    final backend = _FakeBackend();
    backend.listening = {
      backend.tracks.first['path'] as String: {'played': true, 'position': 0},
      backend.tracks.last['path'] as String: {'played': false, 'position': 65},
    };
    await _open(tester, backend);
    expect(find.textContaining('Played'), findsOneWidget);
    expect(find.textContaining('Continue at 1:05'), findsOneWidget);
    expect(backend.mutations('provider.playback_state').single.params, {
      'tracks': backend.tracks,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('all library views fit a 900 by 650 desktop window', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _open(tester, backend, size: const Size(900, 650));
    expect(tester.takeException(), isNull, reason: 'Queue layout overflowed.');
    for (final page in [
      'Play next',
      'Providers',
      'Playlists',
      'Favorites',
      'History',
      'Lyrics',
      'Equalizer',
      'Visualizer',
      'Plugins',
      'Settings',
    ]) {
      await _navigate(tester, page);
      expect(
        tester.takeException(),
        isNull,
        reason: '$page raised a Flutter rendering or layout error.',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(backend.closed, isTrue);
  });
}
