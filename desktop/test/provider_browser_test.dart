import 'dart:async';

import 'package:cliamp_desktop/src/backend.dart';
import 'package:cliamp_desktop/src/provider_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Json = Map<String, dynamic>;

class _ProviderBackend implements PlayerBackend {
  final calls = <({String operation, _Json params})>[];
  final responses = <String, _Json>{};
  final operations = <String>[];
  final _events = StreamController<_Json>.broadcast();
  final _spectrum = StreamController<List<double>>.broadcast();

  _ProviderBackend() {
    responses['provider.browse'] = {
      'browse': {
        'modes': ['genres'],
        'entries': [
          {'id': 'countries', 'name': 'Countries', 'mode': 'genres'},
          {'id': 'tags', 'name': 'Tags', 'mode': 'genres'},
        ],
        'refreshable': true,
        'subscriptions': true,
        'related': true,
        'track_artist': true,
        'location': {
          'needed': true,
          'id': 'nearby',
          'prompt': 'Use your approximate location to find local stations?',
        },
      },
    };
    responses['provider.playlists'] = {
      'playlists': [
        {'id': 'nearby', 'name': 'Nearby stations'},
        {'id': 'saved', 'name': 'Saved stations'},
      ],
      'total': 2,
    };
    responses['provider.genres'] = {
      'genres': [
        {'id': 'CA', 'name': 'Canada', 'group': 'Countries'},
        {'id': 'JP', 'name': 'Japan', 'group': 'Countries', 'favorite': true},
      ],
      'favoritable': true,
      'searchable': true,
      'total': 2,
    };
    responses['provider.genre_tracks'] = {
      'tracks': [
        {
          'path': 'podcast:episode-7',
          'title': 'A thoughtful episode',
          'artist': 'The Field Notes',
          'duration_secs': 600,
          'provider_meta': {
            'podcast.guid': 'episode-7',
            'podcast.feed': 'https://example.org/feed',
          },
        },
      ],
      'listening': {
        'podcast:episode-7': {'played': false, 'position': 120},
      },
      'total': 1,
    };
    responses['provider.subscriptions'] = {
      'subscriptions': [
        {'id': 'show-a', 'name': 'Show A', 'author': 'Alice'},
        {'id': 'show-b', 'name': 'Show B', 'author': 'Bob'},
      ],
      'total': 2,
    };
    responses['provider.location'] = {
      'location': {
        'needed': true,
        'id': 'nearby',
        'prompt': 'Use your approximate location to find local stations?',
      },
    };
    responses['provider.location.consent'] = {
      'location': {'needed': false},
      'place': '',
    };
    responses['provider.genre.favorite'] = {'favorite': true};
  }

  @override
  Future<void> connect() async {}
  @override
  Future<_Json> capabilities() async => {
    'operations': operations.map((name) => {'name': name}).toList(),
  };
  @override
  Future<_Json> snapshot() async => {'playlist_revision': 52};
  @override
  Future<_Json> call(String operation, [_Json params = const {}]) async {
    calls.add((operation: operation, params: Map.of(params)));
    return {'ok': true, ...?responses[operation]};
  }

  @override
  Stream<_Json> get events => _events.stream;
  @override
  Stream<List<double>> get spectrum => _spectrum.stream;
  @override
  Future<void> close() async {
    await _events.close();
    await _spectrum.close();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _ProviderBackend backend, {
  ProviderTrackAction? onPlay,
  ProviderTrackAction? onQueue,
  VoidCallback? onLoaded,
}) async {
  tester.view.physicalSize = const Size(1080, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(backend.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: ProviderBrowser(
          backend: backend,
          provider: const {'key': 'radio', 'name': 'Radio', 'searchable': true},
          onPlayTrack: onPlay ?? (_) async {},
          onQueueTrack: onQueue ?? (_) async {},
          onAddToPlaylist: (_) async {},
          onToggleFavorite: (_) async {},
          onQueueLoaded: onLoaded ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Escape clears provider search and releases editing focus', (
    tester,
  ) async {
    final backend = _ProviderBackend();
    await _mount(tester, backend);
    final search = find.byType(TextField);
    await tester.enterText(search, 'no match');
    await tester.pumpAndSettle();
    expect(find.text('Nearby stations'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('Nearby stations'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
  });

  testWidgets(
    'ordinary track append keeps metadata and does not select playback or play-next',
    (tester) async {
      final backend = _ProviderBackend();
      backend.operations.add('tracks.append');
      final track = <String, dynamic>{
        'title': 'A saved episode',
        'path': 'podcast:episode-42',
        'provider_meta': {
          'podcast.guid': 'episode-42',
          'podcast.feed': 'https://example.org/feed',
        },
        'skip_metadata': true,
        'duration_secs': 400,
      };
      backend.responses['provider.tracks'] = {
        'tracks': [track],
        'total': 1,
      };
      var playbackActions = 0;
      var queueNavigations = 0;
      await _mount(
        tester,
        backend,
        onPlay: (_) async => playbackActions++,
        onQueue: (_) async => playbackActions++,
        onLoaded: () => queueNavigations++,
      );
      await tester.tap(find.text('Saved stations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Track actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(
        backend.calls
            .singleWhere((call) => call.operation == 'tracks.append')
            .params,
        {
          'provider': 'radio',
          'tracks': [track],
          'if_revision': 52,
        },
      );
      expect(playbackActions, 0);
      expect(queueNavigations, 0);
      expect(find.text('Added A saved episode to the queue.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'append resolves the entire filtered collection without replaying loaded pages',
    (tester) async {
      final backend = _ProviderBackend();
      backend.operations.add('provider.collection');
      backend.responses['provider.tracks'] = {
        'tracks': [
          {
            'title': 'Ambient sunrise',
            'path': 'provider:ambient',
            'artist': 'Artist',
          },
        ],
        'total': 1501,
      };
      var navigations = 0;
      await _mount(tester, backend, onLoaded: () => navigations++);
      await tester.tap(find.text('Saved stations'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ambient');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add collection to queue'));
      await tester.pumpAndSettle();
      expect(
        backend.calls
            .singleWhere((call) => call.operation == 'provider.collection')
            .params,
        {
          'provider': 'radio',
          'playlist': 'saved',
          'source': 'playlist',
          'filter': 'ambient',
          'mode': 'append',
          'if_revision': 52,
        },
      );
      expect(
        backend.calls.where((call) => call.operation == 'provider.tracks'),
        hasLength(1),
      );
      expect(
        backend.calls.where(
          (call) =>
              call.operation == 'tracks.append' ||
              call.operation == 'tracks.replace' ||
              call.operation == 'track.play',
        ),
        isEmpty,
      );
      expect(navigations, 0);
      expect(find.text('Added matching tracks to the queue.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'album append expands the album instead of appending its placeholder',
    (tester) async {
      final backend = _ProviderBackend();
      backend.operations.addAll(['provider.collection', 'tracks.append']);
      final album = <String, dynamic>{
        'title': 'Search album',
        'path': 'spotify:album:123',
        'provider_meta': {'kind': 'album', 'albumID': '123'},
      };
      backend.responses['provider.tracks'] = {
        'tracks': [album],
        'total': 1,
      };
      await _mount(tester, backend);
      await tester.tap(find.text('Saved stations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Track actions'));
      await tester.pumpAndSettle();
      expect(find.text('Add to queue'), findsNothing);
      await tester.tap(find.text('Add album to queue'));
      await tester.pumpAndSettle();
      expect(
        backend.calls
            .singleWhere((call) => call.operation == 'provider.collection')
            .params,
        {
          'provider': 'radio',
          'source': 'album',
          'album': '123',
          'track': album,
          'mode': 'append',
          'if_revision': 52,
        },
      );
      expect(
        backend.calls.where((call) => call.operation == 'tracks.append'),
        isEmpty,
      );
    },
  );

  testWidgets('album search records browse or load the complete album', (
    tester,
  ) async {
    final backend = _ProviderBackend();
    backend.operations.add('provider.collection');
    backend.responses['provider.tracks'] = {
      'tracks': [
        {
          'title': 'Search album',
          'path': 'spotify:album:123',
          'provider_meta': {'kind': 'album', 'albumID': '123'},
        },
      ],
      'total': 1,
    };
    await _mount(tester, backend);
    await tester.tap(find.text('Saved stations'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play Search album'));
    await tester.pumpAndSettle();
    final action = backend.calls.lastWhere(
      (call) => call.operation == 'provider.collection',
    );
    expect(action.params, {
      'provider': 'radio',
      'source': 'album',
      'album': '123',
      'track': (backend.responses['provider.tracks']!['tracks'] as List).first,
      'mode': 'play',
      'if_revision': 52,
    });
    expect(
      backend.calls.where(
        (call) =>
            call.operation == 'track.play' ||
            call.operation == 'tracks.replace',
      ),
      isEmpty,
    );
    await tester.tap(find.text('Search album'));
    await tester.pumpAndSettle();
    expect(
      backend.calls
          .lastWhere((call) => call.operation == 'provider.album_tracks')
          .params['album'],
      '123',
    );
  });

  testWidgets(
    'selected playback asks server for the complete large collection',
    (tester) async {
      final backend = _ProviderBackend();
      backend.operations.add('provider.collection');
      backend.responses['provider.tracks'] = {
        'tracks': [
          {
            'title': 'Chosen track',
            'path': 'provider:chosen',
            'artist': 'Artist',
          },
        ],
        'total': 1501,
      };
      await _mount(tester, backend);
      await tester.tap(find.text('Saved stations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play Chosen track'));
      await tester.pumpAndSettle();
      final action = backend.calls.lastWhere(
        (call) => call.operation == 'provider.collection',
      );
      expect(action.params['source'], 'playlist');
      expect(action.params['playlist'], 'saved');
      expect(action.params['selected_path'], 'provider:chosen');
      expect(action.params['mode'], 'play');
      expect(action.params['if_revision'], 52);
      expect(
        backend.calls.where((call) => call.operation == 'provider.tracks'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'country routes, pinned categories and full track metadata survive browsing',
    (tester) async {
      final backend = _ProviderBackend();
      _Json? played;
      await _mount(tester, backend, onPlay: (track) async => played = track);
      await tester.tap(find.widgetWithText(ActionChip, 'Countries'));
      await tester.pumpAndSettle();
      expect(
        backend.calls
            .lastWhere((call) => call.operation == 'provider.genres')
            .params['entry'],
        'countries',
      );
      await tester.tap(find.byTooltip('Pin Canada'));
      await tester.pumpAndSettle();
      expect(
        backend.calls
            .lastWhere((call) => call.operation == 'provider.genre.favorite')
            .params,
        {'provider': 'radio', 'entry': 'countries', 'genre': 'CA'},
      );
      await tester.tap(find.text('Canada'));
      await tester.pumpAndSettle();
      expect(find.text('Continue at 2:00'), findsOneWidget);
      await tester.tap(find.byTooltip('Play A thoughtful episode'));
      await tester.pumpAndSettle();
      expect(played?['provider_meta'], {
        'podcast.guid': 'episode-7',
        'podcast.feed': 'https://example.org/feed',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location remains unused until an explicit answer and denial is preserved',
    (tester) async {
      final backend = _ProviderBackend();
      await _mount(tester, backend);
      expect(
        backend.calls.where(
          (call) => call.operation == 'provider.location.consent',
        ),
        isEmpty,
      );
      await tester.tap(find.text('Nearby stations'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use your approximate location to find local stations?'),
        findsOneWidget,
      );
      expect(
        backend.calls.where(
          (call) => call.operation == 'provider.location.consent',
        ),
        isEmpty,
      );
      await tester.tap(find.text('Do not use location'));
      await tester.pumpAndSettle();
      final consent = backend.calls.singleWhere(
        (call) => call.operation == 'provider.location.consent',
      );
      expect(consent.params['allowed'], isFalse);
      expect(
        backend.calls.where((call) => call.operation == 'provider.tracks'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'newest subscription batches report partial failures without replaying additions',
    (tester) async {
      final backend = _ProviderBackend();
      backend.responses['provider.subscriptions.newest'] = {
        'total': 1,
        'failed': ['Show B'],
      };
      var navigations = 0;
      await _mount(tester, backend, onLoaded: () => navigations++);
      await tester.tap(find.widgetWithText(ActionChip, 'Subscriptions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add newest from all shows'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Some shows could not be loaded: Show B'),
        findsOneWidget,
      );
      final mutations = backend.calls
          .where((call) => call.operation == 'provider.subscriptions.newest')
          .toList();
      expect(mutations, hasLength(1));
      expect(mutations.single.params, {
        'provider': 'radio',
        'mode': 'append',
        'if_revision': 52,
      });
      expect(navigations, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider refresh invalidates source caches rather than just rereading a view',
    (tester) async {
      final backend = _ProviderBackend();
      backend.responses['provider.refresh'] =
          backend.responses['provider.playlists']!;
      await _mount(tester, backend);
      await tester.tap(find.byTooltip('Refresh provider from source'));
      await tester.pumpAndSettle();
      final operations = backend.calls.map((call) => call.operation).toList();
      final refresh = operations.indexOf('provider.refresh');
      expect(refresh, greaterThan(0));
      expect(operations.sublist(refresh), [
        'provider.refresh',
        'provider.playlists',
      ]);
    },
  );
}
