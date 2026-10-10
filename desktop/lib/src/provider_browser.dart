import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend.dart';
import 'fuzzy.dart';

typedef ProviderTrackAction = Future<void> Function(Map<String, dynamic> track);
typedef _Data = Map<String, dynamic>;

List<_Data> _rows(dynamic data) => data is List
    ? data
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
    : [];
_Data _map(dynamic data) => data is Map ? Map<String, dynamic>.from(data) : {};
String _name(dynamic value, [String fallback = '']) =>
    value == null || '$value'.isEmpty ? fallback : '$value';
String _time(dynamic value) {
  final seconds = (value is num ? value.toInt() : 0).clamp(0, 999999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _BrowseView {
  const _BrowseView(
    this.operation,
    this.kind,
    this.title, [
    this.params = const {},
    this.openInPlaylist = false,
  ]);
  final String operation;
  final String kind;
  final String title;
  final _Data params;
  final bool openInPlaylist;
  _BrowseView withParams(_Data params) =>
      _BrowseView(operation, kind, title, params, openInPlaylist);
}

/// Provider-owned browsing and actions. Full TrackInfo maps are forwarded to
/// parent actions so provider identity, episode metadata, and resume flags stay
/// intact. The parent retains shared player chrome and queue navigation.
class ProviderBrowser extends StatefulWidget {
  const ProviderBrowser({
    super.key,
    required this.backend,
    required this.provider,
    required this.onPlayTrack,
    required this.onQueueTrack,
    required this.onAddToPlaylist,
    required this.onToggleFavorite,
    required this.onQueueLoaded,
    this.seedTrack,
    this.initialAction,
    this.searchFocus,
  });
  final PlayerBackend backend;
  final Map<String, dynamic> provider;
  final ProviderTrackAction onPlayTrack;
  final ProviderTrackAction onQueueTrack;
  final ProviderTrackAction onAddToPlaylist;
  final ProviderTrackAction onToggleFavorite;
  final VoidCallback onQueueLoaded;
  final Map<String, dynamic>? seedTrack;
  final String? initialAction;
  final FocusNode? searchFocus;
  @override
  State<ProviderBrowser> createState() => _ProviderBrowserState();
}

class _ProviderBrowserState extends State<ProviderBrowser> {
  Color get _mint => Theme.of(context).colorScheme.primary;
  Color get _dim => Theme.of(context).colorScheme.onSurfaceVariant;
  final _search = TextEditingController();
  _Data _browse = {};
  _Data _response = {};
  List<_Data> _items = [];
  List<_BrowseView> _trail = [];
  _BrowseView _view = const _BrowseView(
    'provider.playlists',
    'playlists',
    'Playlists',
  );
  int _generation = 0;
  int _total = 0;
  int _catalogOffset = 0;
  bool _catalogMore = false;
  bool _loading = true;
  bool _busy = false;
  bool _pinnedOnly = false;
  String _filter = '';
  String? _error;
  String? _notice;
  List<String> _failed = [];
  Set<String> _operations = {};

  String get _provider => _name(widget.provider['key']);
  String get _owner => _name(_view.params['provider'], _provider);
  bool get _genres => _view.kind == 'genres';
  bool get _tracks => _view.kind == 'tracks';
  bool get _subscriptions => _view.kind == 'subscriptions';
  String get _countLabel {
    final plural = _genres ? 'categories' : _view.kind;
    if (_total != 1) return plural;
    return _genres ? 'category' : plural.replaceFirst(RegExp(r's$'), '');
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant ProviderBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider['key'] != widget.provider['key'] ||
        oldWidget.seedTrack != widget.seedTrack ||
        oldWidget.initialAction != widget.initialAction) {
      _trail = [];
      _browse = {};
      _search.clear();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final results = await Future.wait([
        widget.backend.call('provider.browse', {'provider': _provider}),
        widget.backend.capabilities(),
      ]);
      final result = results[0];
      if (!mounted || generation != _generation) return;
      setState(() {
        _browse = _map(result['browse']);
        _operations = _rows(
          results[1]['operations'],
        ).map((item) => _name(item['name'])).toSet();
      });
      if (widget.seedTrack != null && widget.initialAction == 'artist') {
        await _artistFor(widget.seedTrack!);
      } else if (widget.seedTrack != null &&
          widget.initialAction == 'related') {
        await _related(widget.seedTrack!);
      } else {
        await _openMode(_name(_browse['default_mode'], 'playlists'));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _show(
    _BrowseView view, {
    bool push = true,
    bool append = false,
  }) async {
    final generation = ++_generation;
    if (!mounted) return;
    setState(() {
      if (push) _trail = [..._trail, _view];
      _view = view;
      _loading = true;
      _error = null;
      if (!append) {
        _items = [];
        _filter = '';
        _pinnedOnly = false;
      }
    });
    try {
      final result = await widget.backend.call(view.operation, {
        'provider': _provider,
        ...view.params,
        'limit': 100,
        if (append)
          'offset': view.operation == 'provider.catalog'
              ? _catalogOffset
              : _items.length,
      });
      if (result['ok'] == false) {
        throw BackendException(
          _name(result['error'], 'Unable to load this collection.'),
        );
      }
      if (!mounted || generation != _generation) return;
      final rows = _rows(result[view.kind]);
      setState(() {
        final priorListening = append
            ? _map(_response['listening'])
            : <String, dynamic>{};
        _response = {
          ...result,
          if (priorListening.isNotEmpty || result.containsKey('listening'))
            'listening': {...priorListening, ..._map(result['listening'])},
        };
        _items = append && view.operation != 'provider.catalog'
            ? [..._items, ...rows]
            : rows;
        _total = (result['total'] as num?)?.toInt() ?? _items.length;
        _catalogMore = false;
        if (view.operation == 'provider.catalog') {
          _catalogOffset = (append ? _catalogOffset : 0) + _total;
          _catalogMore = _total > 0;
          _total = _items.length;
        }
        _loading = false;
      });
      if (view.kind == 'tracks' && !result.containsKey('listening')) {
        await _readListening(generation, rows);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _readListening(int generation, List<_Data> tracks) async {
    if (tracks.isEmpty) return;
    try {
      final result = await widget.backend.call('provider.playback_state', {
        'provider': _owner,
        'tracks': tracks,
      });
      if (mounted && generation == _generation) {
        setState(
          () => _response = {
            ..._response,
            'listening': {
              ..._map(_response['listening']),
              ..._map(result['listening']),
            },
          },
        );
      }
    } on BackendException catch (error) {
      // Older engines can omit the optional listening-state operation.
      if (error.code != 'unavailable' &&
          error.code != 'unknown_operation' &&
          mounted &&
          generation == _generation) {
        setState(() => _notice = 'Listening progress is unavailable: $error');
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _notice = 'Listening progress is unavailable: $error');
      }
    }
  }

  Future<_Data?> _action(String operation, [_Data params = const {}]) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _failed = [];
    });
    try {
      final changesQueue =
          operation == 'provider.subscription.load' ||
          operation == 'provider.subscriptions.newest' ||
          operation == 'provider.collection' ||
          operation == 'tracks.append' ||
          ((operation == 'provider.related' ||
                  operation == 'provider.genre_tracks') &&
              params['mode'] != null &&
              params['mode'] != 'read');
      final snapshot = changesQueue
          ? await widget.backend.snapshot()
          : const <String, dynamic>{};
      final result = await widget.backend.call(operation, {
        'provider': _owner,
        ...params,
        if (changesQueue) 'if_revision': snapshot['playlist_revision'] ?? 0,
      });
      if (result['ok'] == false) {
        throw BackendException(
          _name(result['error'], 'The action could not be completed.'),
        );
      }
      if (!mounted) return null;
      setState(
        () => _failed = (result['failed'] as List? ?? [])
            .map((name) => '$name')
            .toList(),
      );
      return result;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMode(String mode, {_Data? entry}) async {
    setState(() {
      _trail = [];
      _search.clear();
    });
    final name = _name(entry?['name']);
    final params = <String, dynamic>{if (entry != null) 'entry': entry['id']};
    final openInPlaylist = entry?['open_in_playlist'] == true;
    switch (mode) {
      case 'albums':
        await _show(
          _BrowseView(
            'provider.albums',
            'albums',
            name.isEmpty ? '${_name(_browse['album_label'], 'Album')}s' : name,
            {
              ...params,
              if (_browse['album_sort'] != null) 'sort': _browse['album_sort'],
            },
            openInPlaylist,
          ),
          push: false,
        );
      case 'artists':
      case 'artist_albums':
        await _show(
          _BrowseView(
            'provider.artists',
            'artists',
            name.isEmpty
                ? '${_name(_browse['artist_label'], 'Artist')}s'
                : name,
            params,
            openInPlaylist,
          ),
          push: false,
        );
      case 'genres':
        await _show(
          _BrowseView(
            'provider.genres',
            'genres',
            name.isEmpty ? _name(_browse['genre_label'], 'Genres') : name,
            params,
            openInPlaylist,
          ),
          push: false,
        );
      case 'subscriptions':
        await _show(
          const _BrowseView(
            'provider.subscriptions',
            'subscriptions',
            'Subscriptions',
          ),
          push: false,
        );
      case 'catalog':
        await _show(
          const _BrowseView('provider.catalog', 'playlists', 'Catalog'),
          push: false,
        );
      default:
        await _show(
          const _BrowseView('provider.playlists', 'playlists', 'Playlists'),
          push: false,
        );
    }
  }

  Future<void> _open(_Data item) async {
    final id = _name(item['id']);
    final title = _name(item['name'], 'Collection');
    final owner = <String, dynamic>{
      if (_view.params['provider'] != null)
        'provider': _view.params['provider'],
    };
    final location = _map(_browse['location']);
    if (location['needed'] == true && location['id'] == id) {
      await _locationConsent();
      return;
    }
    switch (_view.kind) {
      case 'genres':
        final params = {..._view.params, 'genre': id};
        if (_view.openInPlaylist) {
          if (await _action('provider.genre_tracks', {
                    ...params,
                    'mode': 'load',
                  }) !=
                  null &&
              mounted) {
            widget.onQueueLoaded();
          }
        } else {
          await _show(
            _BrowseView('provider.genre_tracks', 'tracks', title, params),
          );
        }
      case 'artists':
        await _show(
          _BrowseView('provider.artist_albums', 'albums', title, {
            ...owner,
            'artist': id,
          }, _view.openInPlaylist),
        );
      case 'albums':
        if (_view.openInPlaylist) {
          final operation = _operations.contains('provider.collection')
              ? 'provider.collection'
              : 'provider.load_album';
          if (await _action(operation, {
                    'album': id,
                    if (operation == 'provider.collection') ...{
                      'source': 'album',
                      'mode': 'replace',
                    },
                  }) !=
                  null &&
              mounted) {
            widget.onQueueLoaded();
          }
        } else {
          await _show(
            _BrowseView('provider.album_tracks', 'tracks', title, {
              ...owner,
              'album': id,
            }),
          );
        }
      case 'subscriptions':
        await _show(
          _BrowseView('provider.album_tracks', 'tracks', title, {'album': id}),
        );
      default:
        await _show(
          _BrowseView('provider.tracks', 'tracks', title, {'playlist': id}),
        );
    }
  }

  Future<void> _refresh() async {
    if (_browse['refreshable'] == true) {
      final result = await _action('provider.refresh', {
        if (_view.params['playlist'] != null)
          'playlist': _view.params['playlist'],
      });
      if (result == null) return;
      if (result['playlists'] != null && _view.kind != 'playlists') {
        await _openMode('playlists');
        return;
      }
    }
    await _show(_view, push: false);
  }

  Future<void> _searchProvider(String query) async {
    if (_browse['catalog_search'] == true && _view.kind == 'playlists') {
      await _show(
        _BrowseView(
          'provider.catalog.search',
          'playlists',
          query.trim().isEmpty
              ? (_browse['shows'] == true ? 'Show catalog' : 'Station catalog')
              : (_browse['shows'] == true ? 'Show search' : 'Station search'),
          {'query': query.trim()},
        ),
      );
      return;
    }
    if (query.trim().isEmpty) {
      setState(() => _filter = '');
      return;
    }
    if (_genres && _response['searchable'] == true) {
      await _show(
        _BrowseView(
          'provider.genres',
          'genres',
          'Search ${_view.title.toLowerCase()}',
          {..._view.params, 'query': query.trim()},
        ),
      );
    } else if (widget.provider['searchable'] == true &&
        !_genres &&
        !_subscriptions) {
      await _show(
        _BrowseView('provider.search', 'tracks', 'Search results', {
          'query': query.trim(),
        }),
      );
    } else {
      setState(() => _filter = query.toLowerCase());
    }
  }

  Future<void> _changeSort(String value) async {
    if (_view.operation == 'provider.albums' &&
        _browse['album_sort_savable'] == true) {
      if (await _action('provider.album_sort', {'sort': value}) == null) return;
      _browse['album_sort'] = value;
    }
    await _show(
      _view.withParams({..._view.params, 'sort': value}),
      push: false,
    );
  }

  Future<void> _locationConsent() async {
    final result = await _action('provider.location');
    if (result == null || !mounted) return;
    final location = _map(result['location']);
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local radio'),
        content: Text(
          _name(
            location['prompt'],
            'Allow this provider to use your approximate location to find nearby radio stations?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Do not use location'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow location'),
          ),
        ],
      ),
    );
    // Dismissing is not consent and does not record an answer.
    if (allowed == null) return;
    final saved = await _action('provider.location.consent', {
      'allowed': allowed,
    });
    if (saved != null && mounted) {
      setState(() {
        _browse = {..._browse, 'location': saved['location']};
        _notice = allowed
            ? 'Local radio ${_name(saved['place'])}'.trim()
            : 'Location is disabled.';
      });
      await _openMode('playlists');
    }
  }

  Future<void> _pinGenre(_Data genre) async {
    final result = await _action('provider.genre.favorite', {
      if (_view.params['entry'] != null) 'entry': _view.params['entry'],
      'genre': genre['id'],
    });
    if (result != null && mounted) {
      setState(() => genre['favorite'] = result['favorite'] == true);
    }
  }

  Future<void> _subscriptionAction(String mode, [_Data? show]) async {
    final result = await _action(
      show == null
          ? 'provider.subscriptions.newest'
          : 'provider.subscription.load',
      {'mode': mode, if (show != null) 'playlist': show['id']},
    );
    if (result == null || !mounted) return;
    setState(
      () => _notice = show == null
          ? 'Added the newest episodes from your subscriptions.'
          : 'Updated the queue from ${show['name']}.',
    );
    // Keep partial-feed failures visible here; successful additions are already
    // present in the shared queue and must not be replayed.
    if (_failed.isEmpty && mode == 'play') widget.onQueueLoaded();
  }

  Future<void> _related(_Data track) => _show(
    _BrowseView(
      'provider.related',
      'tracks',
      'Related to ${_name(track['title'], 'this track')}',
      {'track': track, 'mode': 'read'},
    ),
  );

  Future<void> _artistFor(_Data track) async {
    final result = await _action('provider.track_artist', {'track': track});
    if (result == null || !mounted) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final artist = _map(result['artist']);
    setState(() {
      _trail = [..._trail, _view];
      _view = _BrowseView(
        'provider.artist_albums',
        'albums',
        _name(artist['name'], 'Artist'),
        {
          'artist': artist['id'],
          if (result['provider'] != null) 'provider': result['provider'],
        },
      );
      _items = _rows(result['albums']);
      _response = result;
      _total = (result['total'] as num?)?.toInt() ?? _items.length;
      _loading = false;
      _filter = '';
    });
  }

  Future<void> _loadCollection({String mode = 'play'}) async {
    final params = _view.params;
    _Data? result;
    final source = _collectionSource(_view);
    if (mode == 'append' &&
        (!_operations.contains('provider.collection') || source == null)) {
      return;
    }
    if (_operations.contains('provider.collection') && source != null) {
      result = await _action('provider.collection', {
        ...params,
        'source': source,
        'filter': _filter,
        'mode': mode,
      });
    } else if (params['playlist'] != null) {
      result = await _action('provider.load', {'playlist': params['playlist']});
    } else if (params['album'] != null) {
      result = await _action('provider.load_album', {'album': params['album']});
    } else if (_view.operation == 'provider.related') {
      result = await _action('provider.related', {...params, 'mode': 'play'});
    } else if (params['genre'] != null) {
      result = await _action('provider.genre_tracks', {
        ...params,
        'mode': 'play',
      });
    }
    if (result != null && mounted) {
      if (mode == 'append') {
        setState(
          () => _notice = _filter.isEmpty
              ? 'Added the collection to the queue.'
              : 'Added matching tracks to the queue.',
        );
      } else {
        widget.onQueueLoaded();
      }
    }
  }

  String? _collectionSource(_BrowseView view) => switch (view.operation) {
    'provider.tracks' => 'playlist',
    'provider.album_tracks' => 'album',
    'provider.genre_tracks' => 'genre',
    'provider.search' => 'search',
    'provider.related' => 'related',
    _ => null,
  };

  String? _albumId(_Data track) {
    final metadata = _map(track['provider_meta']);
    if (metadata['kind'] != 'album') return null;
    final id = _name(metadata['albumID']);
    return id.isEmpty ? null : id;
  }

  Future<void> _openAlbumResult(_Data track) => _show(
    _BrowseView(
      'provider.album_tracks',
      'tracks',
      _name(track['title'], 'Album'),
      {'album': _albumId(track), 'provider': _owner},
    ),
  );

  Future<void> _trackAction(String action, _Data track) async {
    try {
      final album = _albumId(track);
      if (album != null &&
          const ['open', 'play', 'append', 'next'].contains(action)) {
        if (action == 'open') {
          await _openAlbumResult(track);
        } else {
          final result = await _action('provider.collection', {
            'source': 'album',
            'album': album,
            'track': track,
            'mode': action == 'next' ? 'next' : action,
          });
          if (result != null && mounted) widget.onQueueLoaded();
        }
        return;
      }
      if (album != null && action == 'album_favorite') {
        await _action('provider.favorite', {'playlist': album});
        return;
      }
      switch (action) {
        case 'play':
          await _playVisibleTracks(track);
        case 'append':
          final result = await _action('tracks.append', {
            'tracks': [track],
          });
          if (result != null && mounted) {
            setState(
              () => _notice =
                  'Added ${_name(track['title'], 'track')} to the queue.',
            );
          }
        case 'next':
          await widget.onQueueTrack(track);
        case 'playlist':
          await widget.onAddToPlaylist(track);
        case 'favorite':
          await widget.onToggleFavorite(track);
          if (mounted) await _show(_view, push: false);
        case 'artist':
          await _artistFor(track);
        case 'related':
          await _related(track);
        case 'details':
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Track details'),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final field in const {
                          'title': 'Title',
                          'artist': 'Artist',
                          'album': 'Album',
                          'genre': 'Genre',
                          'year': 'Year',
                          'track_number': 'Track number',
                          'station': 'Station',
                          'path': 'Location',
                        }.entries)
                          if (_name(track[field.key]).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    field.value,
                                    style: TextStyle(color: _dim, fontSize: 11),
                                  ),
                                  const SizedBox(height: 3),
                                  SelectableText(_name(track[field.key])),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _playVisibleTracks(_Data track) async {
    final source = _collectionSource(_view);
    if (_operations.contains('provider.collection') &&
        source != null &&
        track['feed'] != true) {
      final result = await _action('provider.collection', {
        ..._view.params,
        'source': source,
        'filter': _filter,
        'mode': 'play',
        'selected_path': track['path'],
      });
      if (result != null && mounted) widget.onQueueLoaded();
      return;
    }
    if (!_operations.contains('tracks.replace') || track['feed'] == true) {
      await widget.onPlayTrack(track);
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final view = _view;
    final filter = _filter;
    try {
      final all = [..._items];
      while (all.length < _total) {
        final next = await widget.backend.call(view.operation, {
          'provider': _provider,
          ...view.params,
          'offset': all.length,
          'limit': 100,
        });
        final page = _rows(next['tracks']);
        if (page.isEmpty) {
          throw const BackendException(
            'This collection changed while loading. Refresh and try again.',
          );
        }
        all.addAll(page);
      }
      final visible = _filtered(all, filter);
      final selected = visible.indexWhere(
        (item) =>
            item['path'] == track['path'] && item['title'] == track['title'],
      );
      if (selected < 0) {
        throw const BackendException(
          'The selected track is no longer in this collection.',
        );
      }
      if (visible.length > 1000) {
        throw const BackendException(
          'This selection exceeds the player’s track-batch limit. Use Play collection to load the complete source.',
        );
      }
      final snapshot = await widget.backend.snapshot();
      await widget.backend.call('tracks.replace', {
        'tracks': visible,
        'play': true,
        'index': selected,
        'if_revision': snapshot['playlist_revision'] ?? 0,
      });
      if (mounted) widget.onQueueLoaded();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _search.clear();
        FocusScope.of(context).unfocus();
        setState(() => _filter = '');
        if (_name(_view.params['query']).isNotEmpty && _trail.isNotEmpty) {
          var previous = _view;
          do {
            previous = _trail.removeLast();
          } while (_name(previous.params['query']).isNotEmpty &&
              _trail.isNotEmpty);
          _show(previous, push: false);
        }
      },
    },
    child: FocusScope(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: SizedBox(
            height: constraints.maxHeight < 500 ? 500 : constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(),
                if (_loading || _busy)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                if (_error != null) _message(_error!, error: true),
                if (_notice != null) _message(_notice!),
                if (_failed.isNotEmpty)
                  _message(
                    'Some shows could not be loaded: ${_failed.join(', ')}. Successful episodes were added.',
                    error: true,
                  ),
                _breadcrumbs(),
                if (_subscriptions) _subscriptionToolbar(),
                if (_genres || _rows(_response['sorts']).isNotEmpty)
                  _filterToolbar(),
                Expanded(
                  child: _items.isEmpty && !_loading
                      ? _empty()
                      : _tracks
                      ? _trackRows()
                      : _collectionRows(),
                ),
                if (_items.length < _total || _catalogMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () => _show(_view, push: false, append: true),
                      child: Text(
                        _catalogMore
                            ? (_browse['shows'] == true
                                  ? 'Load more shows'
                                  : 'Load more stations')
                            : 'Load more · ${_items.length} of $_total',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toolbar() {
    final entries = _rows(_browse['entries']);
    final modes = (_browse['modes'] as List? ?? [])
        .map((mode) => '$mode')
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: widget.searchFocus,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: _genres
                        ? 'Find a country, tag, or genre…'
                        : _subscriptions
                        ? 'Filter subscribed shows…'
                        : 'Search ${_name(widget.provider['name'], 'this provider')}…',
                  ),
                  onChanged: (value) =>
                      setState(() => _filter = value.toLowerCase()),
                  onSubmitted: _searchProvider,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: _browse['refreshable'] == true
                    ? 'Refresh provider from source'
                    : 'Reload collection',
                onPressed: _busy || _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _route(
                  'Playlists',
                  Icons.library_music_outlined,
                  () => _openMode('playlists'),
                ),
                for (final entry in entries)
                  _route(
                    _name(entry['name']),
                    _routeIcon(_name(entry['mode'])),
                    () => _openMode(_name(entry['mode']), entry: entry),
                  ),
                for (final mode in modes.where(
                  (mode) => !entries.any((entry) => entry['mode'] == mode),
                ))
                  _route(
                    mode == 'albums'
                        ? '${_name(_browse['album_label'], 'Album')}s'
                        : mode == 'genres'
                        ? _name(_browse['genre_label'], 'Genres')
                        : '${_name(_browse['artist_label'], 'Artist')}s',
                    _routeIcon(mode),
                    () => _openMode(mode),
                  ),
                if (_browse['subscriptions'] == true)
                  _route(
                    'Subscriptions',
                    Icons.subscriptions_outlined,
                    () => _openMode('subscriptions'),
                  ),
                if (widget.provider['catalog'] == true)
                  _route(
                    _browse['shows'] == true
                        ? 'Show catalog'
                        : 'Station catalog',
                    Icons.radio_outlined,
                    () => _openMode('catalog'),
                  ),
                if (_map(_browse['location'])['needed'] == true)
                  _route(
                    'Local radio',
                    Icons.location_on_outlined,
                    _locationConsent,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _routeIcon(String mode) => switch (mode) {
    'albums' => Icons.album_outlined,
    'genres' => Icons.public,
    _ => Icons.person_outline,
  };
  Widget _route(String label, IconData icon, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: _busy ? null : onTap,
    ),
  );

  Widget _breadcrumbs() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 10, 28, 12),
    child: Row(
      children: [
        if (_trail.isNotEmpty)
          IconButton(
            tooltip: 'Back to previous collection',
            onPressed: _busy
                ? null
                : () {
                    final previous = _trail.last;
                    setState(
                      () => _trail = _trail.sublist(0, _trail.length - 1),
                    );
                    _show(previous, push: false);
                  },
            icon: const Icon(Icons.arrow_back, size: 19),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _view.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$_total $_countLabel',
                style: TextStyle(color: _dim, fontSize: 11),
              ),
            ],
          ),
        ),
        if (_tracks &&
            _items.isNotEmpty &&
            _operations.contains('provider.collection') &&
            _collectionSource(_view) != null) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _loadCollection(mode: 'append'),
            icon: const Icon(Icons.playlist_add, size: 19),
            label: const Text('Add collection to queue'),
          ),
          const SizedBox(width: 8),
        ],
        if (_tracks &&
            _items.isNotEmpty &&
            (_view.params['playlist'] != null ||
                _view.params['album'] != null ||
                _view.params['genre'] != null ||
                _view.operation == 'provider.related'))
          FilledButton.icon(
            onPressed: _busy ? null : _loadCollection,
            icon: const Icon(Icons.play_arrow_rounded, size: 19),
            label: const Text('Play collection'),
          ),
      ],
    ),
  );

  Widget _filterToolbar() {
    final sorts = _rows(_response['sorts']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_genres && _response['favoritable'] == true)
            FilterChip(
              label: const Text('Pinned only'),
              avatar: const Icon(Icons.push_pin_outlined, size: 15),
              selected: _pinnedOnly,
              onSelected: (selected) => setState(() => _pinnedOnly = selected),
            ),
          if (sorts.isNotEmpty)
            SizedBox(
              width: 240,
              child: DropdownButton<String>(
                isExpanded: true,
                value: sorts.any((sort) => sort['id'] == _view.params['sort'])
                    ? _view.params['sort'] as String
                    : _name(sorts.first['id']),
                underline: const SizedBox.shrink(),
                items: sorts
                    .map(
                      (sort) => DropdownMenuItem(
                        value: _name(sort['id']),
                        child: Text(_name(sort['label'])),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) _changeSort(value);
                      },
              ),
            ),
        ],
      ),
    );
  }

  Widget _subscriptionToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _busy || _items.isEmpty
              ? null
              : () => _subscriptionAction('append'),
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Add newest from all shows'),
        ),
        OutlinedButton.icon(
          onPressed: _busy || _items.isEmpty
              ? null
              : () => _subscriptionAction('next'),
          icon: const Icon(Icons.playlist_play, size: 18),
          label: const Text('Play newest next'),
        ),
      ],
    ),
  );

  List<_Data> _filtered(List<_Data> items, String query) {
    final matches = <({int score, int index, _Data item})>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final score = fuzzyScore(
        query,
        [
          _name(item['name']),
          _name(item['title']),
          _name(item['artist']),
          _name(item['author']),
          _name(item['group']),
        ].join(' '),
      );
      if (score != null) matches.add((score: score, index: i, item: item));
    }
    matches.sort(
      (a, b) => a.score == b.score
          ? a.index.compareTo(b.index)
          : b.score.compareTo(a.score),
    );
    return matches.map((match) => match.item).toList();
  }

  List<_Data> get _visible => _filtered(
    _items.where((item) => !_pinnedOnly || item['favorite'] == true).toList(),
    _filter,
  );

  Widget _collectionRows() {
    final items = _visible;
    if (items.isEmpty) return _empty(filtered: true);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final group = _name(item['section'], _name(item['group']));
        final previous = index == 0
            ? ''
            : _name(
                items[index - 1]['section'],
                _name(items[index - 1]['group']),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (group.isNotEmpty && group != previous)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 9),
                child: Text(
                  group.toUpperCase(),
                  style: TextStyle(
                    color: _dim,
                    letterSpacing: 1.2,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _mint.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _genres
                          ? Icons.public
                          : _subscriptions
                          ? Icons.podcasts
                          : _view.kind == 'artists'
                          ? Icons.person_outline
                          : _view.kind == 'albums'
                          ? Icons.album_outlined
                          : Icons.queue_music,
                      color: _mint,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    _name(item['name'], 'Untitled'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _name(
                      item['author'],
                      _name(
                        item['artist'],
                        item['track_count'] != null
                            ? '${item['track_count']} tracks'
                            : item['album_count'] != null
                            ? '${item['album_count']} albums'
                            : _name(item['section']),
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _dim, fontSize: 11),
                  ),
                  onTap: _busy ? null : () => _open(item),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item['restricted'] == true)
                        Tooltip(
                          message: 'Requires account access',
                          child: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: _dim,
                            ),
                          ),
                        ),
                      if (_genres && _response['favoritable'] == true)
                        IconButton(
                          tooltip: item['favorite'] == true
                              ? 'Unpin ${item['name']}'
                              : 'Pin ${item['name']}',
                          onPressed: _busy ? null : () => _pinGenre(item),
                          icon: Icon(
                            item['favorite'] == true
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            color: item['favorite'] == true ? _mint : _dim,
                            size: 18,
                          ),
                        ),
                      if (!_genres && item['favoritable'] == true)
                        IconButton(
                          tooltip: item['favorite'] == true
                              ? 'Remove favorite'
                              : 'Add favorite',
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await _action('provider.favorite', {
                                        'playlist': item['id'],
                                      }) !=
                                      null) {
                                    await _show(_view, push: false);
                                  }
                                },
                          icon: Icon(
                            item['favorite'] == true
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: item['favorite'] == true ? _mint : _dim,
                          ),
                        ),
                      if (_view.kind == 'albums' &&
                          _browse['album_favorite'] == true &&
                          item['favoritable'] != true)
                        IconButton(
                          tooltip: 'Toggle album favorite',
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await _action('provider.favorite', {
                                            'playlist': item['id'],
                                          }) !=
                                          null &&
                                      mounted) {
                                    setState(
                                      () => _notice = 'Album favorite updated.',
                                    );
                                  }
                                },
                          icon: Icon(
                            Icons.favorite_border,
                            size: 18,
                            color: _dim,
                          ),
                        ),
                      if (_subscriptions || item['show'] == true)
                        PopupMenuButton<String>(
                          requestFocus: true,
                          tooltip: 'Episode actions',
                          enabled: !_busy,
                          onSelected: (mode) => _subscriptionAction(mode, item),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'append',
                              child: Text('Add all episodes'),
                            ),
                            PopupMenuItem(
                              value: 'play',
                              child: Text('Play episodes'),
                            ),
                            PopupMenuItem(
                              value: 'next',
                              child: Text('Queue all episodes next'),
                            ),
                            PopupMenuItem(
                              value: 'newest',
                              child: Text('Add newest episode'),
                            ),
                            PopupMenuItem(
                              value: 'newest_next',
                              child: Text('Play newest episode next'),
                            ),
                          ],
                        ),
                      Icon(Icons.chevron_right, size: 17, color: _dim),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _trackRows() {
    final items = _visible;
    final listening = _map(_response['listening']);
    if (items.isEmpty) return _empty(filtered: true);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final track = items[index];
        final album = _albumId(track);
        final status = _map(listening[_name(track['path'])]);
        final position = (status['position'] as num?)?.toDouble() ?? 0;
        final duration = (track['duration_secs'] as num?)?.toDouble() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            child: ListTile(
              onTap: album == null || _busy
                  ? null
                  : () => _trackAction('open', track),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              leading: IconButton(
                tooltip: 'Play ${_name(track['title'], 'track')}',
                onPressed: _busy || track['unplayable'] == true
                    ? null
                    : () => _trackAction('play', track),
                icon: Icon(Icons.play_arrow_rounded, color: _mint),
              ),
              title: Text(
                _name(track['title'], _name(track['path'])),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(
                      track['artist'],
                      _name(track['album'], 'Unknown artist'),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _dim, fontSize: 11),
                  ),
                  if (album != null)
                    Text(
                      'Album · Open to browse tracks',
                      style: TextStyle(color: _dim, fontSize: 10),
                    ),
                  if (status['played'] == true)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 13,
                            color: _mint,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Played',
                            style: TextStyle(color: _mint, fontSize: 10),
                          ),
                        ],
                      ),
                    )
                  else if (position > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Continue at ${_time(position)}',
                      style: TextStyle(color: _mint, fontSize: 10),
                    ),
                    if (duration > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: (position / duration).clamp(0.0, 1.0),
                          minHeight: 2,
                        ),
                      ),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track['realtime'] == true
                        ? 'LIVE'
                        : duration > 0
                        ? _time(duration)
                        : '—',
                    style: TextStyle(color: _dim, fontSize: 11),
                  ),
                  if (album == null)
                    IconButton(
                      tooltip: track['bookmark'] == true
                          ? 'Remove track favorite'
                          : 'Favorite track',
                      onPressed: _busy
                          ? null
                          : () => _trackAction('favorite', track),
                      icon: Icon(
                        track['bookmark'] == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: track['bookmark'] == true ? _mint : _dim,
                        size: 18,
                      ),
                    ),
                  PopupMenuButton<String>(
                    requestFocus: true,
                    tooltip: 'Track actions',
                    enabled: !_busy,
                    onSelected: (action) => _trackAction(action, track),
                    itemBuilder: (context) => [
                      if (album != null) ...[
                        const PopupMenuItem(
                          value: 'open',
                          child: Text('Open album'),
                        ),
                        const PopupMenuItem(
                          value: 'append',
                          child: Text('Add album to queue'),
                        ),
                        if (_browse['album_favorite'] == true)
                          const PopupMenuItem(
                            value: 'album_favorite',
                            child: Text('Toggle album favorite'),
                          ),
                      ],
                      const PopupMenuItem(
                        value: 'next',
                        child: Text('Play next'),
                      ),
                      if (album == null)
                        const PopupMenuItem(
                          value: 'playlist',
                          child: Text('Add to playlist…'),
                        ),
                      if (album == null &&
                          track['feed'] != true &&
                          _operations.contains('tracks.append'))
                        PopupMenuItem(
                          value: 'append',
                          enabled: track['unplayable'] != true,
                          child: const Text('Add to queue'),
                        ),
                      const PopupMenuItem(
                        value: 'details',
                        child: Text('Track details'),
                      ),
                      if (album == null && _browse['related'] == true)
                        const PopupMenuItem(
                          value: 'related',
                          child: Text('Find related tracks'),
                        ),
                      if (album == null && _browse['track_artist'] == true)
                        PopupMenuItem(
                          value: 'artist',
                          child: Text(
                            'Go to ${_name(_browse['artist_label'], 'artist').toLowerCase()}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _message(String text, {bool error = false}) => Container(
    margin: const EdgeInsets.fromLTRB(28, 5, 28, 5),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Icon(
          error ? Icons.info_outline : Icons.check_circle_outline,
          size: 17,
          color: error
              ? Theme.of(context).colorScheme.onErrorContainer
              : Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: error
                  ? Theme.of(context).colorScheme.onErrorContainer
                  : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        if (error && !_busy)
          IconButton(
            tooltip: 'Retry collection',
            onPressed: () => _show(_view, push: false),
            icon: const Icon(Icons.refresh, size: 16),
          ),
      ],
    ),
  );

  Widget _empty({bool filtered = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _subscriptions
                ? Icons.subscriptions_outlined
                : _genres
                ? Icons.public
                : Icons.library_music_outlined,
            color: _mint,
            size: 34,
          ),
          const SizedBox(height: 16),
          Text(
            filtered
                ? 'No matching items'
                : _subscriptions
                ? 'No subscribed shows yet'
                : 'This collection is empty',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? 'Try another search or turn off the pinned filter.'
                : _subscriptions
                ? 'Favorite a show to keep its episodes here.'
                : 'Refresh or choose another collection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _dim, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
