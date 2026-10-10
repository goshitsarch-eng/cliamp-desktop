import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'backend.dart';
import 'visualizer.dart';
import 'provider_sign_in.dart';
import 'provider_setup.dart';
import 'lyrics.dart';
import 'fuzzy.dart';
import 'provider_browser.dart';
import 'jobs.dart';
import 'preferences.dart';
import 'plugin_manager.dart';
import 'playlist_tools.dart';
import 'desktop_theme.dart';
import 'seek_dialog.dart';

typedef Json = Map<String, dynamic>;

List<Json> _objects(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Json>[];
Json _object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
double _number(dynamic value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;
String _text(dynamic value, [String fallback = '']) =>
    value == null || value.toString().isEmpty ? fallback : value.toString();
String _duration(dynamic value) {
  final seconds = _number(value).round().clamp(0, 999999);
  final minutes = seconds ~/ 60;
  return '${minutes ~/ 60 > 0 ? '${minutes ~/ 60}:' : ''}${minutes ~/ 60 > 0 ? (minutes % 60).toString().padLeft(2, '0') : minutes}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class CliampApp extends StatefulWidget {
  const CliampApp({super.key, this.backend});
  final PlayerBackend? backend;

  @override
  State<CliampApp> createState() => _CliampAppState();
}

class _CliampAppState extends State<CliampApp> {
  late final PlayerBackend _backend = widget.backend ?? CliampBackend();
  DesktopPalette _palette = const DesktopPalette();
  String _themeKey = '';

  void _updateTheme(Json theme) {
    final key = jsonEncode(theme);
    if (!mounted || key == _themeKey) return;
    setState(() {
      _themeKey = key;
      _palette = DesktopPalette.fromEngine(theme);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cliamp',
    debugShowCheckedModeBanner: false,
    theme: _palette.theme,
    home: _Library(backend: _backend, onThemeChanged: _updateTheme),
  );
}

enum _Page {
  queue,
  next,
  providers,
  playlists,
  favorites,
  history,
  lyrics,
  visualizer,
  equalizer,
  plugins,
  settings,
}

const _pageTitles = [
  'Your queue',
  'Play next',
  'Explore providers',
  'Your playlists',
  'Favorites',
  'Recently played',
  'Lyrics',
  'Visualizer',
  'Equalizer',
  'Plugins',
  'Settings',
];
const _pageIcons = [
  Icons.queue_music_rounded,
  Icons.playlist_play_rounded,
  Icons.explore_outlined,
  Icons.library_music_outlined,
  Icons.favorite_border_rounded,
  Icons.history_rounded,
  Icons.lyrics_outlined,
  Icons.graphic_eq_rounded,
  Icons.equalizer_rounded,
  Icons.extension_outlined,
  Icons.tune_rounded,
];
const _navLabels = [
  'Queue',
  'Play next',
  'Providers',
  'Playlists',
  'Favorites',
  'History',
  'Lyrics',
  'Visualizer',
  'Equalizer',
  'Plugins',
  'Settings',
];

class _Library extends StatefulWidget {
  const _Library({required this.backend, required this.onThemeChanged});
  final PlayerBackend backend;
  final ValueChanged<Json> onThemeChanged;
  @override
  State<_Library> createState() => _LibraryState();
}

class _LibraryState extends State<_Library> {
  DesktopPalette _palette = const DesktopPalette();
  Color get _panel => _palette.surface;
  Color get _muted => _palette.muted;
  Color get _accent => _palette.accent;
  Color get _violet => _palette.secondary;
  Color get _foreground => _palette.foreground;
  Json _listening = {};
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _contentFocus = FocusScopeNode();
  final _selectionScroll = ScrollController();
  StreamSubscription<Json>? _events;
  Timer? _positionTicker;
  final _positionClock = Stopwatch();
  StreamSubscription<List<double>>? _spectrum;
  AppLifecycleListener? _lifecycle;
  Future<void> Function()? _restoreAppearance;
  List<Json> _pluginBindings = [];
  Json _state = {};
  List<Json> _operations = [];
  List<Json> _providers = [];
  Json _playlistCapabilities = {};
  String _playlistCapabilityProvider = '';
  List<Json> _items = [];
  List<Json> _sorts = [];
  List<double> _bands = [];
  List<String> _commands = [];
  _Page _page = _Page.queue;
  String _kind = 'tracks';
  String _provider = 'local';
  String _collection = '';
  String _collectionTitle = '';
  final _playlistListUndo = <String, String>{};
  String _request = 'queue.list';
  Json _params = {};
  int _total = 0;
  int? _listRevision;
  int _catalogOffset = 0;
  bool _catalogMore = false;
  int _loadGeneration = 0;
  int _pending = 0;
  bool _connected = false;
  bool _connecting = true;
  bool _loading = false;
  bool _refreshing = false;
  String? _connectionError;
  String? _loadError;
  double? _seekPreview;
  double? _volumePreview;
  String _filter = '';
  final Set<int> _marked = {};
  bool _selecting = false;
  bool _compactPlayer = false;
  int? _selectionAnchor;
  Json? _providerSeed;
  String? _providerAction;
  int _providerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await _restoreAppearance?.call();
        await widget.backend.close();
        return AppExitResponse.exit;
      },
    );
    _positionTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _playing && _state['seekable'] == true) setState(() {});
    });
    _connect();
  }

  Future<void> _connect() async {
    if (mounted) {
      setState(() {
        _connecting = true;
        _connectionError = null;
      });
    }
    try {
      await widget.backend.connect();
      final results = await Future.wait([
        widget.backend.snapshot(),
        widget.backend.capabilities(),
        widget.backend.call('provider.list'),
      ]);
      if (!mounted) return;
      setState(() {
        _state = results[0];
        _positionClock
          ..reset()
          ..start();
        _operations = _objects(results[1]['operations']);
        _providers = _objects(results[2]['providers']);
        _connected = true;
        _connecting = false;
      });
      _updateTheme(_state);
      await _events?.cancel();
      _events = widget.backend.events.listen(
        _onEvent,
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _connectionError = '$error';
              _connected = false;
            });
          }
        },
      );
      await _spectrum?.cancel();
      _spectrum = widget.backend.spectrum.listen((bands) {
        if (!mounted || listEquals(_bands, bands)) return;
        // Only these views paint the spectrum. Keep the latest data for the
        // next navigation without rebuilding unrelated forms at stream rate.
        if (_page == _Page.queue || _page == _Page.equalizer) {
          setState(() => _bands = bands);
        } else {
          _bands = bands;
        }
      }, onError: (Object _) {});
      if (_supports('plugin.keys')) {
        final keys = await widget.backend.call('plugin.keys');
        if (mounted) {
          setState(() => _pluginBindings = _objects(keys['bindings']));
        }
      }
      await _navigate(_page);
    } catch (error) {
      if (mounted) {
        setState(() {
          _connectionError = '$error';
          _connected = false;
          _connecting = false;
        });
      }
    }
  }

  void _onEvent(Json event) {
    if (!mounted) return;
    if (event['event'] == 'runtime.state' ||
        event['topic'] == 'runtime.state') {
      final data = _object(event['data']);
      _acceptState(
        data.containsKey('snapshot') ? _object(data['snapshot']) : data,
      );
    }
  }

  void _updateTheme(Json state) {
    final colors = _object(state['theme']);
    _palette = DesktopPalette.fromEngine(colors);
    widget.onThemeChanged(colors);
  }

  void _acceptState(Json state) {
    if (!mounted || state.isEmpty) return;
    if (_connected &&
        _connectionError == null &&
        jsonEncode(state) == jsonEncode(_state)) {
      return;
    }
    if (_text(state['notice']).isNotEmpty &&
        state['notice'] != _state['notice']) {
      _notice(_text(state['notice']), error: state['notice_error'] == true);
    }
    final revisionChanged =
        state['playlist_revision'] != _state['playlist_revision'];
    final incomingTrack = _object(state['track']);
    final previousTrack = _object(_state['track']);
    final trackChanged = [
      'path',
      'title',
      'artist',
    ].any((field) => incomingTrack[field] != previousTrack[field]);
    setState(() {
      _state = state;
      _positionClock
        ..reset()
        ..start();
      _connected = true;
      _connectionError = null;
    });
    _updateTheme(state);
    if (revisionChanged &&
        (_page == _Page.queue || _page == _Page.next) &&
        !_loading) {
      unawaited(_fetch(_request, _params, kind: 'tracks', quiet: true));
    }
    if (trackChanged && _page == _Page.lyrics) {
      unawaited(_navigate(_Page.lyrics));
    }
  }

  Future<void> _refreshState() async {
    if (!_connected || _refreshing) return;
    _refreshing = true;
    try {
      _acceptState(await widget.backend.snapshot());
    } catch (error) {
      if (mounted) {
        setState(() {
          _connectionError = '$error';
          _connected = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<Json?> _run(
    String operation, [
    Json params = const {},
    String? message,
  ]) async {
    if (!_connected) return null;
    setState(() => _pending++);
    try {
      final result = await widget.backend.call(operation, params);
      if (result['ok'] == false) {
        throw StateError(
          _text(result['error'], 'The operation could not be completed.'),
        );
      }
      await _refreshState();
      if (mounted && message != null) _notice(message);
      return result;
    } catch (error) {
      if (mounted) _notice('$error', error: true);
      if (error is BackendException && error.code == 'conflict') {
        await _refreshState();
        if (mounted && (_page == _Page.queue || _page == _Page.next)) {
          await _refreshList();
        }
      }
      return null;
    } finally {
      if (mounted) setState(() => _pending--);
    }
  }

  void _notice(String message, {bool error = false}) {
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: SingleChildScrollView(
            child: Text(
              message,
              style: TextStyle(
                color: error
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
        backgroundColor: error
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        closeIconColor: error
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onInverseSurface,
        duration: Duration(seconds: error ? 8 : 4),
      ),
    );
  }

  Future<void> _fetch(
    String operation,
    Json params, {
    String kind = 'tracks',
    bool append = false,
    bool quiet = false,
  }) async {
    final generation = ++_loadGeneration;
    final retainQueueView =
        quiet &&
        !append &&
        (operation == 'queue.list' || operation == 'playnext.list');
    final previousItems = _items;
    final requestedRevision = (_state['playlist_revision'] as num?)?.toInt();
    if (!mounted) return;
    setState(() {
      _request = operation;
      _params = params;
      _kind = kind;
      _loading = true;
      _loadError = null;
      if (!append && !quiet) _items = [];
      if (!append && !retainQueueView) {
        _marked.clear();
        _selectionAnchor = null;
      }
      if (_page == _Page.playlists && !append) {
        _playlistCapabilities = {};
        _playlistCapabilityProvider = '';
      }
    });
    try {
      final data = await widget.backend.call(operation, {
        ...params,
        if (kind != 'lyrics' && kind != 'devices') 'limit': 200,
        if (append)
          'offset': operation == 'provider.catalog'
              ? _catalogOffset
              : _items.length,
      });
      if (data['ok'] == false) {
        throw StateError(_text(data['error'], 'Unable to load library.'));
      }
      if (!mounted || generation != _loadGeneration) return;
      final items = _objects(data[kind]);
      if (retainQueueView) {
        final target = math.min(
          previousItems.length,
          (data['total'] as num?)?.toInt() ?? items.length,
        );
        while (items.length < target) {
          final page = await widget.backend.call(operation, {
            ...params,
            'limit': 200,
            'offset': items.length,
          });
          if (!mounted || generation != _loadGeneration) return;
          final more = _objects(page[kind]);
          if (page['ok'] == false || more.isEmpty) {
            throw const BackendException(
              'Unable to refresh the complete queue. Try again.',
            );
          }
          items.addAll(more);
        }
      }
      Json listening = _object(data['listening']);
      if ((kind == 'tracks' || kind == 'history') &&
          items.isNotEmpty &&
          _supports('provider.playback_state')) {
        try {
          final status = await widget.backend.call('provider.playback_state', {
            'tracks': kind == 'history'
                ? items.map((item) => _object(item['track'])).toList()
                : items,
          });
          listening = {...listening, ..._object(status['listening'])};
        } catch (_) {
          // Old engines or unavailable providers can still show playable tracks.
        }
      }
      Json? playlistCapabilities;
      final capabilityProvider = _text(params['provider']);
      if (_page == _Page.playlists &&
          capabilityProvider.isNotEmpty &&
          _supports('playlist.capabilities')) {
        try {
          playlistCapabilities = await widget.backend.call(
            'playlist.capabilities',
            {'provider': capabilityProvider},
          );
        } catch (_) {
          playlistCapabilities = {};
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (playlistCapabilities != null) {
          _playlistCapabilities = playlistCapabilities;
          _playlistCapabilityProvider = capabilityProvider;
        }
        if (retainQueueView &&
            !listEquals(
              previousItems.map((item) => _text(item['path'])).toList(),
              items.map((item) => _text(item['path'])).toList(),
            )) {
          _marked.clear();
          _selectionAnchor = null;
        }
        _listening = append ? {..._listening, ...listening} : listening;
        _items = append && operation != 'provider.catalog'
            ? [..._items, ...items]
            : items;
        _total = (data['total'] as num?)?.toInt() ?? _items.length;
        _sorts = _objects(data['sorts']);
        if (operation == 'queue.list' || operation == 'playnext.list') {
          _listRevision = requestedRevision;
        }
        if (operation == 'provider.catalog') {
          _catalogOffset = (append ? _catalogOffset : 0) + _total;
          _catalogMore = _total > 0;
          _total = _items.length;
        } else {
          _catalogMore = false;
        }
        _loading = false;
      });
      // Runtime events can arrive during a normal navigation or page load too.
      // Reconcile those rows before their captured revision becomes permanent.
      if ((operation == 'queue.list' || operation == 'playnext.list') &&
          requestedRevision != _state['playlist_revision']) {
        unawaited(_fetch(operation, params, kind: kind, quiet: true));
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadError = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _navigate(_Page page) async {
    setState(() {
      _page = page;
      _marked.clear();
      _selecting = false;
      _providerSeed = null;
      _providerAction = null;
      _collection = '';
      _collectionTitle = '';
      _filter = '';
      _search.clear();
      _loadError = null;
      _items = [];
      _total = 0;
      _listRevision = null;
      _catalogMore = false;
      _sorts = [];
      _loading = false;
      _loadGeneration++;
    });
    if (!_connected) return;
    switch (page) {
      case _Page.queue:
        await _fetch('queue.list', {});
      case _Page.next:
        await _fetch('playnext.list', {});
      case _Page.providers:
        if (_providers.isNotEmpty &&
            !_providers.any((p) => p['key'] == _provider)) {
          _provider = _text(_providers.first['key']);
        }
        break;
      case _Page.playlists:
        _provider = 'local';
        await _fetch('provider.playlists', {
          'provider': _provider,
        }, kind: 'playlists');
      case _Page.favorites:
        _provider = 'local';
        _collection = 'Favorites';
        await _fetch('provider.tracks', {
          'provider': 'local',
          'playlist': 'Favorites',
        });
      case _Page.history:
        await _fetch('history', {}, kind: 'history');
      case _Page.lyrics:
        await _fetch('lyrics', {}, kind: 'lyrics');
      case _Page.equalizer:
      case _Page.visualizer:
        break;
      case _Page.plugins:
        if (_supports('plugin.commands')) {
          final result = await _run('plugin.commands');
          if (mounted) {
            setState(
              () => _commands = (result?['items'] as List? ?? [])
                  .map((e) => '$e')
                  .toList(),
            );
          }
        }
      case _Page.settings:
        await _fetch('device', {'name': 'list'}, kind: 'devices');
    }
  }

  bool _supports(String operation) =>
      _operations.any((o) => o['name'] == operation);
  bool _canPlaylist(String action) =>
      _connected &&
      _playlistCapabilityProvider == _provider &&
      _playlistCapabilities[action] == true;
  bool _canRemoveSaved({bool multiple = false}) =>
      _page == _Page.playlists &&
      _collection.isNotEmpty &&
      !['Favorites', 'Recently Played'].contains(_collection) &&
      _canPlaylist(multiple ? 'remove_many' : 'remove');

  Json get _revision => {
    'if_revision': (_page == _Page.queue || _page == _Page.next)
        ? _listRevision ?? _state['playlist_revision'] ?? 0
        : _state['playlist_revision'] ?? 0,
  };
  Json get _track => _object(_state['track']);
  bool get _playing => _state['state'] == 'playing';
  double get _position {
    final base = _number(_state['position']);
    if (!_playing ||
        _state['seekable'] != true ||
        _state['buffering'] == true) {
      return base;
    }
    final duration = _number(_state['duration']);
    final advanced =
        base +
        _positionClock.elapsedMilliseconds / 1000 * _number(_state['speed'], 1);
    return duration > 0 ? advanced.clamp(0, duration) : advanced;
  }

  String get _title => _text(
    _track['title'],
    _track.isEmpty
        ? 'Make room for your music.'
        : _text(_track['path']).split(RegExp(r'[/\\]')).last,
  );

  Future<void> _browseProvider([String tab = 'playlists']) async {
    setState(() {
      _collection = '';
      _collectionTitle = '';
    });
    await _fetch('provider.$tab', {
      'provider': _provider,
    }, kind: tab == 'catalog' ? 'playlists' : tab);
  }

  Future<void> _authenticate(Json provider) async {
    final connected = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProviderSignIn(
        backend: widget.backend,
        provider: _text(provider['key']),
        name: _text(provider['name']),
      ),
    );
    if (connected == true && mounted) {
      _notice('Connected to ${provider['name']}');
      if (_supports('provider.browse')) {
        setState(() => _providerGeneration++);
      } else {
        await _browseProvider();
      }
    }
  }

  Future<void> _configureProvider() async {
    final backend = widget.backend;
    if (backend is! ProviderSetupBackend) return;
    final restarted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ProviderSetupDialog(backend: backend as ProviderSetupBackend),
    );
    if (restarted == true && mounted) {
      await _connect();
    }
  }

  Future<void> _openCollection(Json item) async {
    setState(() {
      _collection = _text(item['id']);
      _collectionTitle = _text(item['name']);
    });
    if (_kind == 'artists') {
      await _fetch('provider.artist_albums', {
        'provider': _provider,
        'artist': _collection,
      }, kind: 'albums');
    } else if (_kind == 'albums') {
      await _fetch('provider.album_tracks', {
        'provider': _provider,
        'album': _collection,
      });
    } else {
      await _fetch('provider.tracks', {
        'provider': _provider,
        'playlist': _collection,
      });
    }
  }

  Future<void> _refreshList() =>
      _fetch(_request, _params, kind: _kind, quiet: true);

  Future<void> _addSource() async {
    try {
      await _importSources();
    } finally {
      // A native chooser can leave focus on the route being dismissed. Restore
      // the library scope so shortcuts still work when the import completes.
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _contentFocus.requestFocus();
      }
    }
  }

  Future<void> _importSources() async {
    var mode = 'append';
    String? inputError;
    final paths = await _showInputDialog<List<String>>(
      context: context,
      builder: (context, controller) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add your music'),
          scrollable: true,
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'append',
                      label: Text('Add to queue'),
                      icon: Icon(Icons.playlist_add),
                    ),
                    ButtonSegment(
                      value: 'replace',
                      label: Text('Replace queue'),
                      icon: Icon(Icons.queue_music),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (values) =>
                      setDialogState(() => mode = values.single),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final files = await openFiles();
                        if (files.isNotEmpty && context.mounted) {
                          Navigator.pop(
                            context,
                            files.map((f) => f.path).toList(),
                          );
                        }
                      },
                      icon: const Icon(Icons.audio_file_outlined),
                      label: const Text('Choose files'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final folders = (await getDirectoryPaths())
                            .whereType<String>()
                            .toList();
                        if (folders.isNotEmpty && context.mounted) {
                          Navigator.pop(context, folders);
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose folders'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    errorText: inputError,
                    labelText: 'File, folder, playlist, URL, or ssh:// path',
                    hintText: 'One source per line',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final lines = controller.text
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (lines.isEmpty) {
                  setDialogState(
                    () => inputError =
                        'Enter a source or choose files or folders.',
                  );
                } else {
                  Navigator.pop(context, lines);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (paths == null || paths.isEmpty || !mounted) return;
    if (mode == 'replace' &&
        _number(_state['total']) > 0 &&
        !await _confirm(
          'Replace the queue?',
          'The selected sources will replace the current queue after they load successfully.',
          'Replace',
        )) {
      return;
    }
    if (_supports('sources.load')) {
      if (await _run('sources.load', {
            'args': paths,
            'name': mode,
            'play': mode == 'replace',
            'if_revision': _state['playlist_revision'] ?? 0,
          }) ==
          null) {
        return;
      }
    } else {
      for (final path in paths) {
        if (await _run('url.load', {'path': path}) == null) return;
      }
    }
    if (mounted) await _navigate(_Page.queue);
  }

  Future<String?> _prompt(
    String title,
    String label, {
    String initial = '',
    String? hint,
    bool multiline = false,
    String action = 'Save',
  }) async {
    String? error;
    final result = await _showInputDialog<String>(
      context: context,
      initial: initial,
      builder: (context, controller) => StatefulBuilder(
        builder: (context, update) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty) {
              update(
                () => error = label == 'Playlist name'
                    ? 'Enter a playlist name.'
                    : 'Enter a value for ${label.toLowerCase()}.',
              );
            } else {
              Navigator.pop(context, value);
            }
          }

          return AlertDialog(
            title: Text(title),
            scrollable: true,
            content: SizedBox(
              width: 460,
              child: TextField(
                controller: controller,
                autofocus: true,
                minLines: multiline ? 3 : 1,
                maxLines: multiline ? 6 : 1,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  errorText: error,
                  alignLabelWithHint: true,
                ),
                onChanged: (_) {
                  if (error != null) update(() => error = null);
                },
                onSubmitted: multiline ? null : (_) => submit(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: Text(action)),
            ],
          );
        },
      ),
    );
    return result;
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _createPlaylist() async {
    if (!_canPlaylist('create')) return;
    final provider = _provider;
    final undoable = _canPlaylist('undo');
    final name = await _prompt(
      'Create a playlist',
      'Playlist name',
      action: 'Create',
    );
    if (name == null) return;
    final result = await _run('playlist.create', {
      'provider': provider,
      'playlist': name,
    }, 'Playlist created');
    if (result != null && mounted) {
      if (undoable) {
        setState(
          () => _playlistListUndo[provider] = _text(result['playlist'], name),
        );
      }
      if (_page == _Page.playlists && _provider == provider) {
        await _refreshList();
      }
    }
  }

  Future<void> _favorite(Json track) async {
    if (await _run('playlist.bookmark', {
          'provider': 'local',
          'track': track,
        }) !=
        null) {
      if (_kind == 'tracks' || _kind == 'history') await _refreshList();
    }
  }

  Future<void> _download() async {
    final result = await _run('save');
    if (result != null && mounted) {
      _notice(
        _text(result['output']).isEmpty
            ? 'Track downloaded'
            : 'Saved to ${result['output']}',
      );
    }
  }

  Future<void> _addToPlaylist(Json track) => _saveTracks([track]);

  Future<void> _trackAction(String action, Json track, int position) async {
    final live = _page == _Page.queue;
    final next = _page == _Page.next;
    final index = live
        ? (track['index'] as num?)?.toInt() ?? position
        : position;
    switch (action) {
      case 'play':
        await _run(live ? 'queue.play' : 'track.play', {
          if (live) 'index': index else 'track': track,
          ..._revision,
        });
      case 'next':
        await _run(live ? 'queue.enqueue' : 'track.queue', {
          if (live) 'index': index else 'track': track,
          ..._revision,
        }, 'Added to play next');
      case 'favorite':
        await _favorite(track);
      case 'playlist':
        await _addToPlaylist(track);
      case 'remove':
        if (!live && !next && !_canRemoveSaved()) return;
        if (await _run(
              live
                  ? 'queue.remove'
                  : next
                  ? 'playnext.remove'
                  : 'playlist.remove',
              {
                if (!live && !next) ...{
                  'provider': _provider,
                  'playlist': _collection,
                },
                'index': index,
                if (live || next) ..._revision,
              },
            ) !=
            null) {
          await _refreshList();
        }
      case 'up':
      case 'down':
        final to = action == 'up' ? index - 1 : index + 1;
        if (to < 0 || to >= _total) return;
        if (await _run(next ? 'playnext.move' : 'queue.move', {
              'index': index,
              'to': to,
              ..._revision,
            }) !=
            null) {
          await _refreshList();
        }
      case 'related':
      case 'artist':
        await _openTrackProvider(track, action);
      case 'details':
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(_text(track['title'], 'Track details')),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(child: _trackDetails(track)),
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
  }

  Future<void> _openTrackProvider(Json track, String action) async {
    final found = await _run(
      action == 'artist' ? 'provider.track_artist' : 'provider.related',
      {'track': track, if (action == 'related') 'limit': 1},
    );
    if (found == null || !mounted) return;
    final key = _text(found['provider']);
    if (key.isEmpty) {
      _notice('This source does not support that action.');
      return;
    }
    await _navigate(_Page.providers);
    if (!mounted) return;
    setState(() {
      _provider = key;
      _providerSeed = track;
      _providerAction = action;
      _providerGeneration++;
    });
  }

  String _trackSearchText(Json item) {
    final track = _kind == 'history' ? _object(item['track']) : item;
    return [
      'title',
      'name',
      'artist',
      'album',
      'path',
      'station',
      'genre',
    ].map((key) => _text(track[key])).join(' ');
  }

  List<MapEntry<int, Json>> get _visibleTracks {
    final scored = <({MapEntry<int, Json> entry, int score})>[];
    for (final entry in _items.asMap().entries) {
      final score = fuzzyScore(_filter, _trackSearchText(entry.value));
      if (score != null) scored.add((entry: entry, score: score));
    }
    scored.sort((a, b) {
      final rank = b.score.compareTo(a.score);
      return rank == 0 ? a.entry.key.compareTo(b.entry.key) : rank;
    });
    return scored.map((item) => item.entry).toList();
  }

  void _mark(int position) => setState(() {
    if (HardwareKeyboard.instance.isShiftPressed && _selectionAnchor != null) {
      final visible = _visibleTracks.map((e) => e.key).toList();
      final from = visible.indexOf(_selectionAnchor!);
      final to = visible.indexOf(position);
      if (from >= 0 && to >= 0) {
        _marked.addAll(
          visible.sublist(math.min(from, to), math.max(from, to) + 1),
        );
      }
    } else if (!_marked.add(position)) {
      _marked.remove(position);
    }
    _selectionAnchor = position;
  });

  void _shortcut(VoidCallback action) {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.findAncestorStateOfType<EditableTextState>() != null ||
        focus?.widget is EditableText) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return;
    action();
  }

  Future<void> _undo() async {
    final live = _page == _Page.queue || _page == _Page.next;
    final provider = _provider;
    final playlist = _collection.isNotEmpty
        ? _collection
        : _playlistListUndo[provider];
    if (!live &&
        (_page != _Page.playlists || playlist == null || playlist.isEmpty)) {
      return;
    }
    if (await _run(
              live ? 'queue.undo' : 'playlist.undo',
              live ? _revision : {'provider': provider, 'playlist': playlist},
            ) !=
            null &&
        mounted) {
      if (!live && _playlistListUndo[provider] == playlist) {
        setState(() => _playlistListUndo.remove(provider));
      }
      await _refreshList();
    }
  }

  Future<void> _commandPalette() async {
    final actions = <(String, String, VoidCallback)>[
      ('Play / pause', 'Space', () => _run('toggle')),
      ('Previous track', 'Ctrl+Left', () => _run('prev')),
      ('Next track', 'Ctrl+Right', () => _run('next')),
      ('Seek back 10 seconds', 'Alt+Left', () => _run('seek', {'value': -10})),
      ('Jump to time', 'Ctrl+J', _jumpToTime),
      (
        'Seek forward 10 seconds',
        'Alt+Right',
        () => _run('seek', {'value': 10}),
      ),
      (
        'Volume up / down',
        'Ctrl+Up / Down',
        () => _run('volume.adjust', {'value': 1}),
      ),
      ('Add files, folder, or URL', 'Ctrl+O', _addSource),
      ('Search this view', 'Ctrl+F', _searchFocus.requestFocus),
      ('Download playing track', 'Ctrl+S', _download),
      ('Undo playlist / queue edit', 'Ctrl+Z', _undo),
      (
        'Compact player',
        'Ctrl+X',
        () => setState(() => _compactPlayer = !_compactPlayer),
      ),
      ('Toggle shuffle', '', () => _run('shuffle', {'name': 'toggle'})),
      ('Cycle repeat', '', () => _run('repeat', {'name': 'cycle'})),
      for (final binding in _pluginBindings)
        (
          '${binding['plugin']}: ${_text(binding['description'], _text(binding['key']))}',
          _text(binding['key']),
          () => _run('plugin.key', {'name': binding['key']}),
        ),
      for (final page in _Page.values)
        ('Open ${_navLabels[page.index]}', '', () => _navigate(page)),
    ];
    var filter = '';
    final chosen = await showDialog<VoidCallback>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Commands & keyboard shortcuts'),
          content: SizedBox(
            width: 560,
            height: 450,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Find a command',
                  ),
                  onChanged: (value) => setDialogState(() => filter = value),
                  onSubmitted: (value) {
                    final matches = actions.where(
                      (action) => fuzzyScore(value, action.$1) != null,
                    );
                    if (matches.isNotEmpty) {
                      Navigator.pop(context, matches.first.$3);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final action in actions)
                        if (fuzzyScore(filter, action.$1) != null)
                          ListTile(
                            title: Text(action.$1),
                            trailing: Text(
                              action.$2,
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                            onTap: () => Navigator.pop(context, action.$3),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    chosen?.call();
  }

  Widget _trackDetails(Json track) {
    const labels = {
      'title': 'Title',
      'artist': 'Artist',
      'album': 'Album',
      'genre': 'Genre',
      'year': 'Year',
      'track_number': 'Track number',
      'station': 'Station',
      'stream_title': 'Now playing',
      'path': 'Path',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in labels.entries)
          if (_text(track[entry.key]).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.value,
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                  SelectableText(_text(track[entry.key])),
                ],
              ),
            ),
        Text('Duration: ${_duration(track['duration_secs'])}'),
        if (track['dir_sourced'] == true)
          const Text('Included by a directory source'),
        if (track['unplayable'] == true)
          const Text('This source cannot play this item.'),
        if (track['restricted'] == true)
          const Text('This item requires permission or a subscription.'),
        ExpansionTile(
          title: const Text('Additional metadata'),
          children: [
            SelectableText(const JsonEncoder.withIndent('  ').convert(track)),
          ],
        ),
      ],
    );
  }

  Widget _selectionToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(32, 0, 24, 8),
    child: Scrollbar(
      controller: _selectionScroll,
      thumbVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      child: SingleChildScrollView(
        controller: _selectionScroll,
        padding: const EdgeInsets.only(bottom: 8),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('${_marked.length} selected'),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => setState(() {
                final visible = _visibleTracks.map((e) => e.key);
                if (visible.every(_marked.contains)) {
                  _marked.removeAll(visible);
                } else {
                  _marked.addAll(visible);
                }
              }),
              child: const Text('Select visible'),
            ),
            TextButton(
              onPressed: _marked.isEmpty ? null : () => _batchTracks('append'),
              child: const Text('Append'),
            ),
            TextButton(
              onPressed: _marked.isEmpty ? null : () => _batchTracks('next'),
              child: const Text('Play next'),
            ),
            TextButton(
              onPressed: _marked.isEmpty ? null : () => _batchTracks('replace'),
              child: const Text('Replace queue'),
            ),
            TextButton(
              onPressed: _marked.isEmpty ? null : () => _batchTracks('save'),
              child: const Text('Save to playlist'),
            ),
            if (_page == _Page.queue ||
                _page == _Page.next ||
                _canRemoveSaved(multiple: true))
              TextButton(
                onPressed: _marked.isEmpty
                    ? null
                    : () => _batchTracks('remove'),
                child: const Text('Remove'),
              ),
            IconButton(
              tooltip: 'Finish selecting',
              onPressed: () => setState(() {
                _selecting = false;
                _marked.clear();
              }),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _batchTracks(String action) async {
    final positions = _marked.toList()..sort();
    final tracks = positions
        .where((i) => i < _items.length)
        .map(
          (i) => _kind == 'history' ? _object(_items[i]['track']) : _items[i],
        )
        .toList();
    if (tracks.isEmpty) return;
    if (action == 'save') {
      await _saveTracks(tracks);
      return;
    }
    if (action == 'remove') {
      if (_page != _Page.queue &&
          _page != _Page.next &&
          !_canRemoveSaved(multiple: true)) {
        return;
      }
      if (!await _confirm(
        'Remove ${tracks.length} tracks?',
        'The selected entries will be removed from this list.',
        'Remove',
      )) {
        return;
      }
      final live = _page == _Page.queue || _page == _Page.next;
      await _run(
        _page == _Page.queue
            ? 'queue.remove_many'
            : _page == _Page.next
            ? 'playnext.remove_many'
            : 'playlist.remove_many',
        {
          'indexes': [
            for (final position in positions)
              _page == _Page.queue
                  ? _items[position]['index'] ?? position
                  : position,
          ],
          'tracks': tracks,
          if (live) ..._revision,
          if (!live) ...{'provider': _provider, 'playlist': _collection},
        },
      );
    } else if (action == 'next') {
      await _run('tracks.enqueue', {'tracks': tracks, ..._revision});
    } else {
      if (action == 'replace' &&
          _number(_state['total']) > 0 &&
          !await _confirm(
            'Replace the queue?',
            'The selected tracks become the current playlist.',
            'Replace',
          )) {
        return;
      }
      await _run(action == 'replace' ? 'tracks.replace' : 'tracks.append', {
        'tracks': tracks,
        ..._revision,
        'play': action == 'replace',
      });
    }
    if (mounted) await _refreshList();
  }

  Future<void> _saveTracks(List<Json> tracks) async {
    final destinations = <Json>[];
    for (final provider in _providers) {
      final key = _text(provider['key']);
      final caps = _supports('playlist.capabilities')
          ? await _run('playlist.capabilities', {'provider': key})
          : key == 'local'
          ? <String, dynamic>{'add_many': true, 'create': true, 'prepend': true}
          : null;
      if (caps == null || caps['add_many'] != true) continue;
      var offset = 0;
      while (mounted) {
        final list = await _run('provider.playlists', {
          'provider': key,
          'offset': offset,
          'limit': 200,
        });
        if (list == null) break;
        final playlists = _objects(list['playlists']);
        if (playlists.isEmpty) break;
        for (final playlist in playlists) {
          if (key == 'local' &&
              ['Favorites', 'Recently Played'].contains(playlist['id'])) {
            continue;
          }
          if (_supports('playlist.capabilities')) {
            final target = await _run('playlist.capabilities', {
              'provider': key,
              'playlist': playlist['id'],
            });
            if (target?['can_add'] == false) continue;
          }
          destinations.add({
            ...playlist,
            'provider': key,
            'provider_name': provider['name'],
            'capabilities': caps,
          });
        }
        offset += playlists.length;
        final total = (list['total'] as num?)?.toInt();
        if (total != null ? offset >= total : playlists.length < 200) break;
      }
      if (caps['create'] == true) {
        destinations.add({
          'new': true,
          'provider': key,
          'provider_name': provider['name'],
          'capabilities': caps,
        });
      }
    }
    if (!mounted) return;
    var prepend = false;
    final selected = await showDialog<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Save ${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'} to playlist',
          ),
          content: SizedBox(
            width: 480,
            height: 380,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Place at the beginning'),
                  subtitle: const Text(
                    'Supported playlists move existing explicit tracks to the front.',
                  ),
                  value: prepend,
                  onChanged: (value) => setDialogState(() => prepend = value),
                ),
                Expanded(
                  child: destinations.isEmpty
                      ? const Center(
                          child: Text(
                            'No writable playlist providers are available.',
                          ),
                        )
                      : ListView(
                          children: [
                            for (final item in destinations)
                              ListTile(
                                enabled:
                                    !prepend ||
                                    _object(item['capabilities'])['prepend'] ==
                                        true,
                                leading: Icon(
                                  item['new'] == true
                                      ? Icons.add
                                      : Icons.playlist_add,
                                ),
                                title: Text(
                                  item['new'] == true
                                      ? 'New playlist'
                                      : _text(item['name']),
                                ),
                                subtitle: Text(_text(item['provider_name'])),
                                onTap: () => Navigator.pop(context, item),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final provider = _text(selected['provider']);
    var name = _text(selected['id']);
    if (selected['new'] == true) {
      final value = await _prompt(
        'Create playlist',
        'Playlist name',
        action: 'Create',
      );
      if (value == null) return;
      final created = await _run('playlist.create', {
        'provider': provider,
        'playlist': value,
      });
      if (created == null) return;
      name = _text(created['playlist'], value);
    }
    final result = await _run(
      prepend ? 'playlist.prepend' : 'playlist.add_many',
      {'provider': provider, 'playlist': name, 'tracks': tracks},
    );
    if (result != null && mounted) {
      _notice(
        'Playlist updated${result['skipped'] != null ? ' · ${result['skipped']} skipped' : ''}',
      );
    }
  }

  @override
  void dispose() {
    _positionTicker?.cancel();
    _lifecycle?.dispose();
    _events?.cancel();
    _spectrum?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _contentFocus.dispose();
    _selectionScroll.dispose();
    unawaited(widget.backend.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    key: _messenger,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _addSource,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _shortcut(() => _run('toggle')),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ): () =>
            _shortcut(() => _run('next')),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
        ): () =>
            _shortcut(() => _run('prev')),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _shortcut(() => _run('seek', {'value': 10})),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _shortcut(() => _run('seek', {'value': -10})),
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
            _shortcut(() => _run('volume.adjust', {'value': 1})),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
        ): () =>
            _shortcut(() => _run('volume.adjust', {'value': -1})),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _shortcut(_undo),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _shortcut(_download),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            _shortcut(_jumpToTime),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _commandPalette,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _addSource,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            _shortcut(_undo),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            _shortcut(_download),
        const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): () =>
            _shortcut(_jumpToTime),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _commandPalette,
        const SingleActivator(LogicalKeyboardKey.f1): _commandPalette,
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () =>
            _shortcut(() => setState(() => _compactPlayer = !_compactPlayer)),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (ModalRoute.of(context)?.isCurrent != true) {
            Navigator.of(context).maybePop();
            return;
          }
          _search.clear();
          _searchFocus.unfocus();
          setState(() {
            _filter = '';
            _marked.clear();
            _selecting = false;
            _compactPlayer = false;
          });
        },
      },
      child: FocusScope(
        node: _contentFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || _pluginBindings.isEmpty) {
            return KeyEventResult.ignored;
          }
          final focus = FocusManager.instance.primaryFocus?.context;
          if (focus?.findAncestorStateOfType<EditableTextState>() != null ||
              focus?.widget is EditableText ||
              ModalRoute.of(context)?.isCurrent != true) {
            return KeyEventResult.ignored;
          }
          final keyboard = HardwareKeyboard.instance;
          final key = [
            if (keyboard.isControlPressed) 'ctrl',
            if (keyboard.isAltPressed) 'alt',
            if (keyboard.isMetaPressed) 'super',
            if (keyboard.isShiftPressed) 'shift',
            event.logicalKey.keyLabel.toLowerCase(),
          ].join('+');
          if (!_pluginBindings.any((binding) => binding['key'] == key)) {
            return KeyEventResult.ignored;
          }
          _run('plugin.key', {'name': key});
          return KeyEventResult.handled;
        },
        child: Scaffold(
          bottomNavigationBar: _playerBar(MediaQuery.sizeOf(context).width),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 860;
              return Column(
                children: [
                  if (!_compactPlayer)
                    Expanded(
                      child: Row(
                        children: [
                          _sidebar(compact),
                          Expanded(
                            child: Column(
                              children: [
                                _topbar(compact),
                                if (_pending > 0 || _connecting)
                                  const LinearProgressIndicator(minHeight: 2)
                                else
                                  const SizedBox(height: 2),
                                if (_connectionError != null)
                                  _connectionBanner(),
                                if (_text(_state['stream_error']).isNotEmpty)
                                  _errorBanner(_text(_state['stream_error'])),
                                Expanded(
                                  child: !_connected
                                      ? _connectionView()
                                      : _content(constraints.maxWidth),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_compactPlayer)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 130,
                              height: 130,
                              child: _Artwork(track: _track, large: true),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _compactPlayer = false),
                              icon: const Icon(Icons.open_in_full),
                              label: const Text('Open library'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _sidebar(bool compact) => Container(
    width: compact ? 76 : 218,
    decoration: BoxDecoration(
      color: _palette.sidebar,
      border: Border(
        right: BorderSide(color: _foreground.withValues(alpha: .05)),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 19 : 26, 27, 20, 30),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: _palette.onAccent,
                  size: 24,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 11),
                const Expanded(
                  child: Text(
                    'cliamp',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
            children: [
              if (!compact)
                _eyebrow(
                  'YOUR MUSIC',
                  padding: const EdgeInsets.fromLTRB(14, 0, 0, 13),
                ),
              for (final page in _Page.values) ...[
                if (page == _Page.lyrics)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Divider(color: _foreground.withValues(alpha: .06)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Tooltip(
                    message: compact ? _navLabels[page.index] : '',
                    child: Material(
                      color: page == _page
                          ? _accent.withValues(alpha: .10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => _navigate(page),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 16 : 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _pageIcons[page.index],
                                size: 21,
                                color: page == _page ? _accent : _muted,
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Text(
                                    _navLabels[page.index],
                                    style: TextStyle(
                                      fontWeight: page == _page
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: page == _page ? _accent : _muted,
                                    ),
                                  ),
                                ),
                                if (page == _Page.queue &&
                                    _number(_state['total']) > 0)
                                  Text(
                                    '${_state['total']}',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: compact
              ? Icon(
                  _connected
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: _connected ? _accent : _muted,
                  size: 19,
                )
              : Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _connected ? _accent : _muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _connected ? 'Engine connected' : 'Engine offline',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );

  Widget _topbar(bool compact) => Padding(
    padding: EdgeInsets.fromLTRB(
      compact ? 20 : 32,
      MediaQuery.sizeOf(context).height < 650 ? 8 : 22,
      compact ? 20 : 32,
      MediaQuery.sizeOf(context).height < 650 ? 8 : 18,
    ),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: _page == _Page.providers && _supports('provider.browse')
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Explore your music',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                : TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: _page == _Page.providers
                          ? 'Search this provider…'
                          : 'Search your music…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded, size: 17),
                              onPressed: () {
                                _search.clear();
                                setState(() => _filter = '');
                              },
                            ),
                    ),
                    onChanged: (value) =>
                        setState(() => _filter = value.toLowerCase()),
                    onSubmitted: (value) {
                      if (_page == _Page.providers && value.trim().isNotEmpty) {
                        _collectionTitle = 'Search results';
                        _collection = '';
                        _fetch('provider.search', {
                          'provider': _provider,
                          'query': value.trim(),
                        });
                      }
                    },
                  ),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.backend is JobProgressBackend)
          _icon(
            Icons.task_alt,
            'Background activity',
            () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: SizedBox(
                  width: 600,
                  child: JobsPanel(
                    backend: widget.backend as JobProgressBackend,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        _icon(
          Icons.keyboard_outlined,
          'Keyboard shortcuts and commands',
          _commandPalette,
        ),
        const SizedBox(width: 8),
        if (!compact)
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Text(
              'ALL YOUR MUSIC. ONE PLACE.',
              style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.3),
            ),
          ),
        FilledButton.icon(
          onPressed: _connected ? _addSource : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(compact ? 'Add' : 'Add music'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
        ),
      ],
    ),
  );

  Widget _connectionBanner() =>
      _errorBanner(_connectionError!, retry: _connect);
  Widget _errorBanner(String message, {VoidCallback? retry}) => Container(
    color: Theme.of(context).colorScheme.errorContainer,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
  Widget _connectionView() => _empty(
    _connecting ? Icons.graphic_eq_rounded : Icons.power_off_rounded,
    _connecting ? 'Opening your music space' : 'Let’s reconnect your player',
    _connecting
        ? 'Starting the Cliamp audio engine…'
        : 'The audio engine could not be reached. Check that the Cliamp engine is installed beside the app, then retry.',
    action: _connecting ? null : _connect,
    label: 'Retry connection',
  );

  Widget _content(double width) {
    if (_page == _Page.providers && _supports('provider.browse')) {
      final provider =
          _providers.where((p) => p['key'] == _provider).firstOrNull ??
          <String, dynamic>{};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _providerToolbar(),
          Expanded(
            child: ProviderBrowser(
              key: ValueKey('$_provider:$_providerGeneration'),
              backend: widget.backend,
              provider: provider,
              searchFocus: _searchFocus,
              seedTrack: _providerSeed,
              initialAction: _providerAction,
              onPlayTrack: (track) async {
                await _run('track.play', {'track': track, ..._revision});
              },
              onQueueTrack: (track) async {
                await _run('track.queue', {'track': track, ..._revision});
              },
              onAddToPlaylist: _addToPlaylist,
              onToggleFavorite: (track) async {
                await _run('playlist.bookmark', {
                  'provider': 'local',
                  'track': track,
                });
              },
              onQueueLoaded: () {
                _refreshState();
                _navigate(_Page.queue);
              },
            ),
          ),
        ],
      );
    }

    if (_page == _Page.equalizer) return _equalizer();
    if (_page == _Page.visualizer) {
      return EngineVisualizer(
        backend: widget.backend,
        playbackState: _state,
        operations: _operations,
        onError: (error) => _notice(error, error: true),
        onCleanupReady: (cleanup) => _restoreAppearance = cleanup,
      );
    }
    if (_page == _Page.settings) return _settings();
    if (_page == _Page.plugins) return _plugins();
    if (_page == _Page.lyrics) return _lyrics();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _libraryHeader(width),
        if (_page == _Page.providers || _page == _Page.playlists)
          _providerToolbar(),
        _listToolbar(),
        if (_selecting) _selectionToolbar(),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: _loadError != null
              ? _empty(
                  Icons.wifi_off_rounded,
                  'Couldn’t load this view',
                  _loadError!,
                  action: _refreshList,
                  label: 'Try again',
                )
              : _items.isEmpty && !_loading
              ? _emptyForPage()
              : (_kind == 'tracks' || _kind == 'history')
              ? _trackList(width)
              : _collectionGrid(),
        ),
        if (_items.length < _total || _catalogMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => _fetch(_request, _params, kind: _kind, append: true),
              child: Text(
                _catalogMore
                    ? 'Load more from catalog'
                    : 'Load more · ${_items.length} of $_total',
              ),
            ),
          ),
      ],
    );
  }

  Widget _libraryHeader(double width) {
    final queue = _page == _Page.queue;
    final count = queue ? (_state['total'] as num? ?? 0) : _total;
    final plural = _kind == 'history' ? 'plays' : _kind;
    final noun = count == 1 && plural.endsWith('s')
        ? plural.substring(0, plural.length - 1)
        : plural;
    final countLabel = '$count $noun';
    final title = _collectionTitle.isNotEmpty
        ? _collectionTitle
        : _pageTitles[_page.index];
    if (MediaQuery.sizeOf(context).height < 650) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(countLabel, style: TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 7, 32, 18),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: _palette.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _foreground.withValues(alpha: .055)),
      ),
      child: Row(
        children: [
          if (width > 730) ...[
            SizedBox(
              width: 115,
              height: 115,
              child: _Artwork(
                track: queue ? _track : {},
                icon: _pageIcons[_page.index],
                large: true,
              ),
            ),
            const SizedBox(width: 26),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _eyebrow(
                  queue
                      ? 'LISTEN WITHOUT LIMITS'
                      : _page == _Page.providers
                      ? 'CONNECTED MUSIC'
                      : 'YOUR COLLECTION',
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  queue
                      ? 'Your next favorite moment starts here.'
                      : _page == _Page.providers
                      ? 'Local collections, streaming services, radio & more.'
                      : _page == _Page.next
                      ? 'A little intention for what comes after this.'
                      : _page == _Page.favorites
                      ? 'The tracks you always come back to.'
                      : _page == _Page.history
                      ? 'Pick up where the music took you.'
                      : 'Soundtracks for every part of your day.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      queue ? '$countLabel in queue' : countLabel,
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                    if (queue && _playing) ...[
                      const SizedBox(width: 18),
                      Icon(Icons.graphic_eq, color: _accent, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        'Now playing',
                        style: TextStyle(fontSize: 11, color: _accent),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (width > 1100 && queue)
            SizedBox(
              width: 160,
              height: 82,
              child: CustomPaint(
                painter: _SpectrumPainter(
                  _bands,
                  playing: _playing,
                  accent: _accent,
                  secondary: _violet,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _providerToolbar() {
    final provider =
        _providers.where((p) => p['key'] == _provider).firstOrNull ?? {};
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            DropdownButton<String>(
              value: _providers.any((p) => p['key'] == _provider)
                  ? _provider
                  : null,
              underline: const SizedBox.shrink(),
              items: _providers
                  .map(
                    (p) => DropdownMenuItem(
                      value: _text(p['key']),
                      child: Text(_text(p['name'])),
                    ),
                  )
                  .toList(),
              hint: const Text('Choose provider'),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _provider = value;
                    _providerSeed = null;
                    _providerAction = null;
                    _providerGeneration++;
                  });
                  if (_page != _Page.providers ||
                      !_supports('provider.browse')) {
                    _browseProvider();
                  }
                }
              },
            ),
            const SizedBox(width: 22),
            if (widget.backend is ProviderSetupBackend)
              _chip(
                'Connect service',
                Icons.add_link_rounded,
                _configureProvider,
              ),
            if (_page != _Page.providers || !_supports('provider.browse'))
              _chip(
                'Playlists',
                Icons.library_music_outlined,
                () => _browseProvider(),
                selected: _kind == 'playlists',
              ),
            if (provider['browse_artists'] == true &&
                (_page != _Page.providers || !_supports('provider.browse')))
              _chip(
                'Artists',
                Icons.person_outline,
                () => _browseProvider('artists'),
                selected: _kind == 'artists',
              ),
            if (provider['browse_albums'] == true &&
                (_page != _Page.providers || !_supports('provider.browse')))
              _chip(
                'Albums',
                Icons.album_outlined,
                () => _browseProvider('albums'),
                selected: _kind == 'albums',
              ),
            if (provider['catalog'] == true &&
                (_page != _Page.providers || !_supports('provider.browse')))
              _chip('Catalog', Icons.public, () => _browseProvider('catalog')),
            if (provider['authenticatable'] == true &&
                _supports('provider.auth'))
              TextButton.icon(
                onPressed: () => _authenticate(provider),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Sign in'),
              ),
            if (_kind == 'albums' && _sorts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: DropdownButton<String>(
                  value: _sorts.any((sort) => sort['id'] == _params['sort'])
                      ? _params['sort'] as String
                      : _text(_sorts.first['id']),
                  underline: const SizedBox.shrink(),
                  items: _sorts
                      .map(
                        (sort) => DropdownMenuItem(
                          value: _text(sort['id']),
                          child: Text(_text(sort['label'])),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _fetch('provider.albums', {
                        'provider': _provider,
                        'sort': value,
                      }, kind: 'albums');
                    }
                  },
                ),
              ),
            if (_collectionTitle.isNotEmpty)
              TextButton.icon(
                onPressed: _browseProvider,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back to browse'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 15, color: selected ? _accent : _muted),
      label: Text(
        label,
        style: TextStyle(fontSize: 11, color: selected ? _accent : _muted),
      ),
      side: BorderSide(
        color: selected
            ? _accent.withValues(alpha: .3)
            : _foreground.withValues(alpha: .07),
      ),
      backgroundColor: selected
          ? _accent.withValues(alpha: .06)
          : Colors.transparent,
    ),
  );

  Widget _listToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(32, 0, 24, 10),
    child: Row(
      children: [
        Text(
          _kind == 'tracks'
              ? 'Tracks'
              : _kind == 'history'
              ? 'Listening history'
              : _kind == 'playlists'
              ? 'Made for listening'
              : _kind == 'albums'
              ? 'Albums'
              : 'Artists',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 9),
        Text('$_total', style: TextStyle(color: _muted, fontSize: 12)),
        const Spacer(),
        if (_kind == 'tracks' || _kind == 'history')
          _icon(
            Icons.checklist,
            'Select tracks',
            () => setState(() {
              _selecting = !_selecting;
              if (!_selecting) _marked.clear();
            }),
            active: _selecting,
          ),
        if ((_page == _Page.queue || _page == _Page.next) &&
            _supports('queue.undo'))
          _icon(Icons.undo, 'Undo last queue edit', _undo),
        if (_page == _Page.playlists &&
            _kind == 'playlists' &&
            _playlistListUndo.containsKey(_provider) &&
            _canPlaylist('undo'))
          _icon(Icons.undo, 'Undo last playlist edit', _undo),
        if (_page == _Page.playlists &&
            _kind == 'playlists' &&
            _canPlaylist('create'))
          TextButton.icon(
            onPressed: _createPlaylist,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('New playlist'),
          ),
        if (_page == _Page.playlists &&
            _collection.isNotEmpty &&
            !['Favorites', 'Recently Played'].contains(_collection) &&
            ['directories', 'undo', 'sort', 'move', 'import'].any(_canPlaylist))
          _icon(
            Icons.edit_note,
            'Playlist tools: files, directories, sorting and undo',
            _playlistTools,
          ),
        if (_page == _Page.queue && _items.isNotEmpty)
          _icon(Icons.save_outlined, 'Save queue as playlist', _saveQueue),
        if ((_page == _Page.queue ||
                _page == _Page.next ||
                _page == _Page.history) &&
            _items.isNotEmpty)
          _icon(
            Icons.delete_sweep_outlined,
            'Clear ${_navLabels[_page.index].toLowerCase()}',
            () async {
              if (await _confirm(
                'Clear ${_navLabels[_page.index].toLowerCase()}?',
                'This removes the entries from this list. Your music files are kept.',
                'Clear',
              )) {
                await _run(
                  _page == _Page.queue
                      ? 'queue.clear'
                      : _page == _Page.next
                      ? 'playnext.clear'
                      : 'history.clear',
                  _page == _Page.history ? {} : _revision,
                );
                await _refreshList();
              }
            },
          ),
        if (_collection.isNotEmpty &&
            _kind == 'tracks' &&
            (_page == _Page.providers || _page == _Page.playlists))
          TextButton.icon(
            onPressed: () async {
              final album = _request == 'provider.album_tracks';
              if (await _run(album ? 'provider.load_album' : 'provider.load', {
                    'provider': _provider,
                    album ? 'album' : 'playlist': _collection,
                  }) !=
                  null) {
                await _navigate(_Page.queue);
              }
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Load collection'),
          ),
        _icon(Icons.refresh_rounded, 'Refresh', _refreshList),
      ],
    ),
  );

  Future<void> _playlistTools() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => PlaylistToolsDialog(
        backend: widget.backend,
        provider: _provider,
        playlist: _collection,
      ),
    );
    if (changed == true && mounted) await _refreshList();
  }

  Future<void> _saveQueue() async {
    final name = await _prompt('Save queue as playlist', 'Playlist name');
    if (name == null) return;
    await _run('playlist.save_queue', {
      'provider': 'local',
      'playlist': name,
      ..._revision,
    }, 'Queue saved as $name');
  }

  String _trackDuration(Json track) {
    if (track['realtime'] == true) return 'LIVE';
    var seconds = _number(track['duration_secs']);
    if (seconds <= 0 &&
        track['path'] != null &&
        track['path'] == _track['path']) {
      seconds = _number(_state['duration']);
    }
    return seconds > 0 ? _duration(seconds) : '—';
  }

  Widget _trackList(double width) {
    final entries = _visibleTracks;
    if (entries.isEmpty) {
      return _empty(
        Icons.search_rounded,
        'No matching tracks',
        'Try another title, artist, or album.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(47, 4, 43, 11),
          child: Row(
            children: [
              SizedBox(
                width: 33,
                child: Text('#', style: TextStyle(color: _muted, fontSize: 11)),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  'TITLE',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (width > 1040)
                Expanded(
                  flex: 3,
                  child: Text(
                    'ALBUM',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              SizedBox(
                width: 104,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.schedule_rounded, size: 14, color: _muted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            itemCount: entries.length,
            itemBuilder: (context, row) {
              final position = entries[row].key;
              final item = entries[row].value;
              final track = _kind == 'history' ? _object(item['track']) : item;
              final current =
                  _track['path'] != null && track['path'] == _track['path'];
              final disabled = track['unplayable'] == true;
              final listening = _object(_listening[_text(track['path'])]);
              final played = listening['played'] == true;
              final resume = _number(listening['position']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: _marked.contains(position)
                      ? _violet.withValues(alpha: .14)
                      : current
                      ? _accent.withValues(alpha: .065)
                      : row.isOdd
                      ? _foreground.withValues(alpha: .016)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _selecting ? () => _mark(position) : null,
                    onDoubleTap: disabled
                        ? null
                        : () => _trackAction('play', track, position),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          if (_selecting)
                            Checkbox(
                              value: _marked.contains(position),
                              semanticLabel:
                                  'Select ${_text(track['title'], 'track ${position + 1}')}',
                              onChanged: (_) => _mark(position),
                            ),
                          SizedBox(
                            width: 40,
                            child: current && _playing
                                ? Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 17,
                                    color: _accent,
                                  )
                                : _icon(
                                    Icons.play_arrow_rounded,
                                    'Play ${_text(track['title'], 'track ${position + 1}')}',
                                    disabled
                                        ? null
                                        : () => _trackAction(
                                            'play',
                                            track,
                                            position,
                                          ),
                                    size: 18,
                                  ),
                          ),
                          SizedBox(
                            width: 42,
                            height: 42,
                            child: _Artwork(track: track),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _text(
                                    track['title'],
                                    _text(
                                      track['path'],
                                      'Untitled track',
                                    ).split(RegExp(r'[/\\]')).last,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: disabled
                                        ? _muted
                                        : current
                                        ? _accent
                                        : _foreground,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _text(
                                    track['artist'],
                                    _text(
                                      track['station'],
                                      track['stream'] == true
                                          ? 'Live stream'
                                          : 'Unknown artist',
                                    ),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: _muted, fontSize: 11),
                                ),
                                if (played || resume > 0)
                                  Text(
                                    played
                                        ? 'Played'
                                        : 'Continue at ${_duration(resume)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _accent,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (width > 1040)
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  _kind == 'history'
                                      ? _historyDate(item['played_at'])
                                      : _text(track['album'], '—'),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                              ),
                            ),
                          _icon(
                            track['bookmark'] == true
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            track['bookmark'] == true
                                ? 'Remove favorite'
                                : 'Add favorite',
                            () => _favorite(track),
                            size: 17,
                            active: track['bookmark'] == true,
                          ),
                          SizedBox(
                            width: 47,
                            child: Text(
                              _trackDuration(track),
                              textAlign: TextAlign.right,
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ),
                          PopupMenuButton<String>(
                            requestFocus: true,
                            enabled: _connected,
                            tooltip: 'Track actions',
                            icon: Icon(
                              Icons.more_horiz,
                              color: _muted,
                              size: 19,
                            ),
                            onSelected: (action) =>
                                _trackAction(action, track, position),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'next',
                                child: Text('Play next'),
                              ),
                              const PopupMenuItem(
                                value: 'playlist',
                                child: Text('Add to playlist…'),
                              ),
                              if (_page == _Page.queue ||
                                  _page == _Page.next) ...[
                                if (position > 0)
                                  const PopupMenuItem(
                                    value: 'up',
                                    child: Text('Move up'),
                                  ),
                                if (position < _items.length - 1)
                                  const PopupMenuItem(
                                    value: 'down',
                                    child: Text('Move down'),
                                  ),
                              ],
                              if (_page == _Page.queue ||
                                  _page == _Page.next ||
                                  _canRemoveSaved())
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove from list'),
                                ),
                              if (_supports('provider.related'))
                                const PopupMenuItem(
                                  value: 'related',
                                  child: Text('Related tracks'),
                                ),
                              if (_supports('provider.track_artist'))
                                const PopupMenuItem(
                                  value: 'artist',
                                  child: Text('Go to artist'),
                                ),
                              const PopupMenuItem(
                                value: 'details',
                                child: Text('Track details'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _historyDate(dynamic value) {
    final date = DateTime.tryParse(_text(value))?.toLocal();
    return date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _collectionGrid() {
    final entries = _items
        .where(
          (item) =>
              _filter.isEmpty ||
              fuzzyScore(_filter, _trackSearchText(item)) != null,
        )
        .toList();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        mainAxisExtent: 222,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final item = entries[index];
        return Material(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _openCollection(item),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: _Artwork(
                        track: {'title': item['name']},
                        icon: _kind == 'artists'
                            ? Icons.person_outline_rounded
                            : _kind == 'albums'
                            ? Icons.album_outlined
                            : item['id'] == 'Favorites'
                            ? Icons.favorite_rounded
                            : Icons.queue_music_rounded,
                        large: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _text(item['name'], 'Untitled'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_kind == 'playlists')
                        SizedBox(
                          height: 24,
                          width: 26,
                          child: PopupMenuButton<String>(
                            requestFocus: true,
                            enabled: _connected,
                            padding: EdgeInsets.zero,
                            tooltip: 'Playlist actions',
                            icon: Icon(
                              Icons.more_horiz,
                              size: 19,
                              color: _muted,
                            ),
                            onSelected: (action) =>
                                _playlistAction(action, item),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'load',
                                child: Text('Load playlist'),
                              ),
                              if (item['favoritable'] == true)
                                PopupMenuItem(
                                  value: 'favorite',
                                  child: Text(
                                    item['favorite'] == true
                                        ? 'Remove favorite'
                                        : 'Add favorite',
                                  ),
                                ),
                              if (![
                                'Favorites',
                                'Recently Played',
                              ].contains(item['id'])) ...[
                                if (_canPlaylist('rename'))
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename…'),
                                  ),
                                if (_canPlaylist('delete'))
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete…'),
                                  ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                  Text(
                    _text(
                      item['artist'],
                      item['track_count'] != null
                          ? '${item['track_count']} ${item['track_count'] == 1 ? 'track' : 'tracks'}'
                          : item['album_count'] != null
                          ? '${item['album_count']} ${item['album_count'] == 1 ? 'album' : 'albums'}'
                          : _text(item['section'], _provider),
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _playlistAction(String action, Json item) async {
    if ((action == 'rename' || action == 'delete') && !_canPlaylist(action)) {
      return;
    }
    final params = {'provider': _provider, 'playlist': item['id']};
    final provider = _provider;
    final undoable = _canPlaylist('undo');
    switch (action) {
      case 'load':
        if (await _run('provider.load', params) != null) {
          await _navigate(_Page.queue);
        }
      case 'favorite':
        await _run('provider.favorite', params);
        await _refreshList();
      case 'rename':
        final name = await _prompt(
          'Rename playlist',
          'Playlist name',
          initial: _text(item['name']),
        );
        if (name != null &&
            await _run('playlist.rename', {...params, 'new_name': name}) !=
                null &&
            mounted) {
          if (undoable) {
            setState(() => _playlistListUndo[provider] = name);
          }
          await _refreshList();
        }
      case 'delete':
        if (await _confirm(
              'Delete ${item['name']}?',
              'This deletes the saved playlist. Your music files are kept.',
              'Delete',
            ) &&
            await _run('playlist.delete', params) != null &&
            mounted) {
          if (undoable) {
            setState(() => _playlistListUndo[provider] = _text(item['id']));
          }
          await _refreshList();
        }
    }
  }

  Widget _emptyForPage() => switch (_page) {
    _Page.queue => _empty(
      Icons.library_music_outlined,
      'Your music belongs here',
      'Add a file, folder, playlist, or stream.\nEverything you love, in one listening space.',
      action: _addSource,
      label: 'Add your first tracks',
    ),
    _Page.next => _empty(
      Icons.playlist_play_rounded,
      'Choose what comes next',
      'Use a track’s menu to add it to Play next.',
    ),
    _Page.favorites => _empty(
      Icons.favorite_border_rounded,
      'Keep the good ones close',
      'Tap the heart beside any track to find it here.',
    ),
    _Page.history => _empty(
      Icons.history_rounded,
      'Your listening story starts here',
      'Tracks appear here as you listen.',
    ),
    _Page.playlists => _empty(
      Icons.library_music_outlined,
      'A playlist for every mood',
      _canPlaylist('create')
          ? 'Create your first playlist and add tracks from any collection.'
          : 'This provider has no saved playlists to show.',
      action: _canPlaylist('create') ? _createPlaylist : null,
      label: 'Create playlist',
    ),
    _ => _empty(
      Icons.explore_outlined,
      'Nothing here yet',
      'Try another collection or search this provider.',
    ),
  };

  Widget _empty(
    IconData icon,
    String title,
    String description, {
    VoidCallback? action,
    String? label,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _accent.withValues(alpha: .09)),
            ),
            child: Icon(icon, color: _accent, size: 30),
          ),
          const SizedBox(height: 19),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12, height: 1.7),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add, size: 17),
              label: Text(label ?? 'Continue'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _lyrics() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionHeader(
        'Every word. Every feeling.',
        _track.isEmpty
            ? 'Play a track to find its lyrics.'
            : '$_title · ${_text(_track['artist'])}',
        trailing: _icon(Icons.refresh, 'Refresh lyrics', _refreshList),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: _loadError != null
            ? _empty(
                Icons.lyrics_outlined,
                'Lyrics unavailable',
                _loadError!,
                action: _refreshList,
                label: 'Try again',
              )
            : _items.isEmpty
            ? _empty(
                Icons.lyrics_outlined,
                'Let the music speak',
                'No lyrics are available for this track.',
              )
            : SyncedLyrics(
                lines: _items,
                position: _position,
                offsetMs: _number(_state['lyrics_offset_ms']).toInt(),
                onOffsetChanged: _supports('lyrics.offset')
                    ? (value) => _run('lyrics.offset', {'value': value})
                    : null,
                realtime: _track['realtime'] == true,
                seekable: _state['seekable'] == true,
                onSeek: (value) => _run('seek.absolute', {'value': value}),
              ),
      ),
    ],
  );

  Widget _equalizer() {
    final values = (_state['eq_bands'] as List? ?? List.filled(10, 0))
        .map((v) => _number(v))
        .toList();
    const labels = [
      '70',
      '180',
      '320',
      '600',
      '1k',
      '3k',
      '6k',
      '12k',
      '14k',
      '16k',
    ];
    const presets = [
      'Flat',
      'Rock',
      'Pop',
      'Jazz',
      'Classical',
      'Bass Boost',
      'Treble Boost',
      'Vocal',
      'Electronic',
      'Acoustic',
      'Hip-Hop',
      'R&B',
      'Loudness',
      'Late Night',
      'Podcast',
      'Small Speakers',
      'Custom',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 36),
      children: [
        _heading(
          'Fine-tune your listening.',
          'A ten-band equalizer, shaped around your sound.',
        ),
        const SizedBox(height: 27),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.equalizer, color: _accent),
                  const SizedBox(width: 12),
                  const Text(
                    'Equalizer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: presets.contains(_state['eq_preset'])
                        ? _state['eq_preset'] as String
                        : 'Flat',
                    items: presets
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _run('eq', {'name': value});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 270,
                child: Row(
                  children: List.generate(
                    10,
                    (index) => Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${(index < values.length ? values[index] : 0).toStringAsFixed(0)} dB',
                            style: TextStyle(color: _muted, fontSize: 10),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _BandSlider(
                              value: index < values.length ? values[index] : 0,
                              onChanged: (value) =>
                                  _run('eq', {'band': index, 'value': value}),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            labels[index],
                            style: TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              Text(
                'Frequency · Hz',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Container(
          height: 150,
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: CustomPaint(
            painter: _SpectrumPainter(
              _bands,
              playing: _playing,
              accent: _accent,
              secondary: _violet,
            ),
          ),
        ),
      ],
    );
  }

  Widget _settings() => ListView(
    padding: const EdgeInsets.fromLTRB(32, 14, 32, 36),
    children: [
      if (widget.backend is DesktopManagementBackend)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: FilledButton.icon(
            onPressed: () => _openManagement(false),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('All preferences'),
          ),
        ),

      _heading(
        'Make yourself at home.',
        'Playback preferences and your connected music services.',
      ),
      const SizedBox(height: 27),
      Material(
        color: _panel,
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Mono audio'),
              subtitle: Text(
                'Combine both channels for a single output.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              value: _state['mono'] == true,
              onChanged: (value) =>
                  _run('mono', {'name': value ? 'on' : 'off'}),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Playback speed'),
              subtitle: Text(
                'Adjust the pace of music, podcasts, and audiobooks.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              trailing: _speedMenu(),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Audio output'),
              subtitle: Text(
                _text(_state['device'], 'System default'),
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              trailing: _icon(
                Icons.refresh,
                'Refresh audio devices',
                _refreshList,
              ),
            ),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_loadError!, style: TextStyle(color: _muted)),
              ),
            for (final device in _items)
              ListTile(
                dense: true,
                leading: Icon(
                  device['active'] == true
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: device['active'] == true ? _accent : _muted,
                  size: 18,
                ),
                title: Text(
                  _text(device['name']),
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () async {
                  await _run('device', {'name': device['name']});
                  await _refreshList();
                },
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connected providers',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _providers
                  .map(
                    (p) => Chip(
                      avatar: Icon(
                        Icons.check_circle_outline,
                        color: _accent,
                        size: 15,
                      ),
                      label: Text(
                        _text(p['name']),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'The desktop app shares Cliamp’s provider accounts, music library, plugins, and preferences. Connect a service here, or use cliamp setup from a terminal.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.7),
            ),
            const SizedBox(height: 12),
            if (widget.backend is ProviderSetupBackend)
              FilledButton.icon(
                onPressed: _configureProvider,
                icon: const Icon(Icons.add_link_rounded, size: 17),
                label: const Text('Connect service'),
              ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _showText(
                'Provider setup',
                'Choose Connect service to configure an account, then follow its sign-in instructions. You can also use cliamp setup from a terminal.\n\nAccounts and preferences are shared with the terminal player.\n\nFFmpeg and yt-dlp extend supported streaming formats. Your existing installations are reused.',
              ),
              icon: const Icon(Icons.info_outline, size: 17),
              label: const Text('Setup instructions'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Advanced controls',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Access additional commands supported by your running player.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: _operationDialog,
              icon: const Icon(Icons.code_rounded, size: 17),
              label: Text('Browse ${_operations.length} engine operations'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Cliamp Desktop  ·  Built for listening.\nCtrl+O  Add music     Ctrl+F  Search',
        style: TextStyle(color: _muted, fontSize: 11, height: 1.8),
      ),
    ],
  );

  Widget _plugins() => ListView(
    padding: const EdgeInsets.fromLTRB(32, 14, 32, 36),
    children: [
      if (widget.backend is DesktopManagementBackend)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: FilledButton.icon(
            onPressed: () => _openManagement(true),
            icon: const Icon(Icons.extension_outlined),
            label: const Text('Manage plugins'),
          ),
        ),

      _heading(
        'A little more possibility.',
        'Your existing Lua plugins, connected to the same audio engine.',
      ),
      const SizedBox(height: 28),
      for (final binding in _pluginBindings)
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: Text(_text(binding['description'], 'Keyboard action')),
          subtitle: Text('${binding['plugin']} · ${binding['key']}'),
          trailing: const Icon(Icons.play_arrow),
          onTap: () => _run('plugin.key', {'name': binding['key']}),
        ),
      if (_commands.isEmpty)
        SizedBox(
          height: 280,
          child: _empty(
            Icons.extension_outlined,
            'Your player, extended',
            _supports('plugin.commands')
                ? 'No plugin commands are registered. Open Manage plugins to install or enable plugins, then restart the engine.'
                : 'Plugins are unavailable in the current engine.',
          ),
        ),
      for (final command in _commands)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: _panel,
            borderRadius: BorderRadius.circular(15),
            child: ListTile(
              leading: Icon(Icons.extension_outlined, color: _violet),
              title: Text(command),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              onTap: () => _pluginCommand(command),
            ),
          ),
        ),
      if (_supports('plugin.call'))
        OutlinedButton.icon(
          onPressed: () => _pluginCommand(''),
          icon: const Icon(Icons.terminal, size: 18),
          label: const Text('Run plugin command'),
        ),
    ],
  );

  Future<void> _openManagement(bool plugins) async {
    final backend = widget.backend;
    if (backend is! DesktopManagementBackend) return;
    final restarted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => plugins
          ? PluginManagerDialog(backend: backend as DesktopManagementBackend)
          : PreferencesDialog(backend: backend as DesktopManagementBackend),
    );
    if (restarted == true && mounted) await _connect();
  }

  Future<void> _pluginCommand(String command) async {
    final parts = command.split(RegExp(r'\s+'));
    final name = await _prompt(
      'Run plugin command',
      'Plugin name',
      initial: parts.firstOrNull ?? '',
      action: 'Continue',
    );
    if (name == null) return;
    final sub = await _prompt(
      'Command for $name',
      'Command',
      initial: parts.length > 1 ? parts[1] : '',
      action: 'Continue',
    );
    if (sub == null) return;
    final args = await _prompt(
      'Command arguments',
      'JSON array of arguments',
      initial: '[]',
      action: 'Run',
    );
    if (args == null) return;
    try {
      final parsed = jsonDecode(args);
      if (parsed is! List || parsed.any((e) => e is! String)) {
        throw const FormatException(
          'Arguments must be a JSON array of strings.',
        );
      }
      final result = await _run('plugin.call', {
        'name': name,
        'sub': sub,
        'args': parsed,
      });
      if (result != null) {
        await _showText(
          'Plugin result',
          _text(result['output'], 'Command completed.'),
        );
      }
    } catch (error) {
      _notice('$error', error: true);
    }
  }

  Future<void> _showText(String title, String text) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(child: SelectableText(text)),
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

  Future<void> _operationDialog() async {
    if (_operations.isEmpty) return;
    Json selected = _operations.first;
    String? error;
    final request = await _showInputDialog<Json>(
      context: context,
      initial: '{}',
      builder: (context, controller) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Engine operations'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _text(selected['name']),
                    items: _operations
                        .map(
                          (o) => DropdownMenuItem(
                            value: _text(o['name']),
                            child: Text(
                              _text(o['name']),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() {
                      selected = _operations.firstWhere(
                        (o) => o['name'] == value,
                      );
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _text(selected['description']),
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Parameters: ${(selected['parameters'] as List? ?? []).join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    minLines: 4,
                    maxLines: 10,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Parameters (JSON object)',
                      alignLabelWithHint: true,
                      errorText: error,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final params = jsonDecode(controller.text);
                  if (params is! Map<String, dynamic>) {
                    throw const FormatException('Enter a JSON object.');
                  }
                  Navigator.pop(context, {
                    'operation': selected['name'],
                    'params': params,
                  });
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
              child: const Text('Run operation'),
            ),
          ],
        ),
      ),
    );
    if (request != null) {
      final result = await _run(
        _text(request['operation']),
        _object(request['params']),
      );
      if (result != null) {
        await _showText(
          'Operation result',
          const JsonEncoder.withIndent('  ').convert(result),
        );
      }
    }
  }

  Widget _sectionHeader(String title, String subtitle, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 15, 32, 20),
        child: Row(
          children: [
            Expanded(child: _heading(title, subtitle)),
            ?trailing,
          ],
        ),
      );
  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 8),
      Text(subtitle, style: TextStyle(color: _muted, fontSize: 12)),
    ],
  );
  BoxDecoration _cardDecoration() => BoxDecoration(
    color: _panel,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(color: _foreground.withValues(alpha: .04)),
  );
  Widget _eyebrow(String text, {EdgeInsets padding = EdgeInsets.zero}) =>
      Padding(
        padding: padding,
        child: Text(
          text,
          style: TextStyle(
            color: _muted,
            fontSize: 9,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
  Widget _icon(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool active = false,
    double size = 21,
  }) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, size: size),
    color: active ? _accent : _muted,
    onPressed: onPressed,
  );

  Widget _speedMenu() => PopupMenuButton<double>(
    requestFocus: true,
    enabled: _connected,
    tooltip: 'Playback speed',
    initialValue: _number(_state['speed'], 1),
    onSelected: (value) => _run('speed', {'value': value}),
    itemBuilder: (context) => [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0]
        .map((value) => PopupMenuItem(value: value, child: Text('$value×')))
        .toList(),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        '${_number(_state['speed'], 1).toStringAsFixed(_number(_state['speed'], 1) % 1 == 0 ? 0 : 2)}×',
        style: TextStyle(fontSize: 11, color: _muted),
      ),
    ),
  );

  Widget _playerBar(double width) {
    final narrow = width < 780;
    final position = _seekPreview ?? _position;
    final duration = _number(_state['duration']);
    final volumeFloor = _number(
      _state['volume_min'],
      math.min(-50, _number(_state['volume'])),
    ).clamp(-90.0, 0.0);
    final volume = (_volumePreview ?? _number(_state['volume'])).clamp(
      volumeFloor,
      6.0,
    );
    return Container(
      height: narrow ? 148 : 112,
      decoration: BoxDecoration(
        color: _panel,
        border: Border(
          top: BorderSide(color: _foreground.withValues(alpha: .08)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(narrow ? 15 : 26, 12, narrow ? 15 : 26, 10),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: narrow ? 46 : 58,
                  height: narrow ? 46 : 58,
                  child: _Artwork(track: _track),
                ),
                const SizedBox(width: 13),
                Expanded(
                  flex: narrow ? 3 : 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _track.isEmpty ? 'Ready when you are' : _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _text(
                          _track['artist'],
                          _track.isEmpty
                              ? 'Add music to get started'
                              : _track['realtime'] == true
                              ? 'Live stream'
                              : 'Unknown artist',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (!narrow)
                  _icon(
                    Icons.favorite_border,
                    'Favorite current track',
                    _track.isEmpty ? null : () => _favorite(_track),
                    size: 18,
                  ),
                Expanded(
                  flex: narrow ? 5 : 7,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!narrow)
                            _icon(
                              Icons.shuffle_rounded,
                              'Shuffle',
                              _connected
                                  ? () => _run('shuffle', {'name': 'toggle'})
                                  : null,
                              active: _state['shuffle'] == true,
                              size: 18,
                            ),
                          _icon(
                            Icons.skip_previous_rounded,
                            'Previous track',
                            _connected ? () => _run('prev') : null,
                            size: 25,
                          ),
                          const SizedBox(width: 5),
                          IconButton.filled(
                            tooltip: _playing ? 'Pause' : 'Play',
                            onPressed: _connected ? () => _run('toggle') : null,
                            icon: Icon(
                              _playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 28,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: _palette.onAccent,
                              fixedSize: const Size(43, 43),
                            ),
                          ),
                          const SizedBox(width: 5),
                          _icon(
                            Icons.skip_next_rounded,
                            'Next track',
                            _connected ? () => _run('next') : null,
                            size: 25,
                          ),
                          if (!narrow)
                            _icon(
                              _text(_state['repeat']).toLowerCase() == 'one'
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              'Repeat: ${_text(_state['repeat'], 'off')}',
                              _connected
                                  ? () => _run('repeat', {'name': 'cycle'})
                                  : null,
                              active:
                                  _state['repeat'] != null &&
                                  _text(_state['repeat']).toLowerCase() !=
                                      'off',
                              size: 18,
                            ),
                        ],
                      ),
                      if (!narrow) _seekBar(position, duration),
                    ],
                  ),
                ),
                if (width > 1030) ...[
                  _speedMenu(),
                  _icon(
                    Icons.download_outlined,
                    'Download current track',
                    _track.isEmpty ? null : _download,
                    size: 18,
                  ),
                  _icon(
                    Icons.lyrics_outlined,
                    'Show lyrics',
                    () => _navigate(_Page.lyrics),
                    size: 18,
                  ),
                ],
                if (!narrow) ...[
                  _icon(
                    volume <= volumeFloor
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    volume <= volumeFloor ? 'Restore volume' : 'Minimum volume',
                    _connected
                        ? () => _run('volume', {
                            'value': volume <= volumeFloor ? 0 : volumeFloor,
                          })
                        : null,
                    size: 20,
                  ),
                  SizedBox(
                    width: width > 1100 ? 95 : 64,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        key: ValueKey(('volume', _connected)),
                        value: volume,
                        min: volumeFloor,
                        max: 6,
                        onChanged: _connected
                            ? (value) => setState(() => _volumePreview = value)
                            : null,
                        onChangeEnd: (value) async {
                          await _run('volume', {'value': value});
                          if (mounted) setState(() => _volumePreview = null);
                        },
                        semanticFormatterCallback: (value) =>
                            '${value.round()} decibels',
                      ),
                    ),
                  ),
                ],
                PopupMenuButton<String>(
                  requestFocus: true,
                  enabled: _connected,
                  tooltip: 'Playback options',
                  icon: Icon(Icons.more_vert, color: _muted, size: 18),
                  onSelected: (action) {
                    if (action == 'download') {
                      _download();
                    } else if (action == 'volume') {
                      _adjustVolume(volumeFloor);
                    } else if (action == 'mono') {
                      _run('mono', {'name': 'toggle'});
                    } else if (action == 'shuffle') {
                      _run('shuffle', {'name': 'toggle'});
                    } else if (action == 'repeat') {
                      _run('repeat', {'name': 'cycle'});
                    } else {
                      _run('stop');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'stop',
                      child: Text('Stop playback'),
                    ),
                    const PopupMenuItem(
                      value: 'download',
                      child: Text('Download track'),
                    ),
                    const PopupMenuItem(
                      value: 'volume',
                      child: Text('Adjust volume…'),
                    ),
                    PopupMenuItem(
                      value: 'mono',
                      child: Text(
                        _state['mono'] == true
                            ? 'Switch to stereo'
                            : 'Switch to mono',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'shuffle',
                      child: Text('Toggle shuffle'),
                    ),
                    PopupMenuItem(
                      value: 'repeat',
                      child: Text('Repeat: ${_text(_state['repeat'], 'off')}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (narrow) _seekBar(position, duration),
        ],
      ),
    );
  }

  Future<void> _adjustVolume(double minimum) async {
    var value = _number(_state['volume']).clamp(minimum, 6.0);
    final selected = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Volume'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${value.toStringAsFixed(1)} dB'),
                Slider(
                  value: value,
                  min: minimum,
                  max: 6,
                  onChanged: (next) => update(() => value = next),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _run('volume', {'value': selected});
  }

  Future<void> _jumpToTime() async {
    if (!_connected || _state['seekable'] != true) return;
    final path = _text(_track['path']);
    final position = await showSeekDialog(
      context,
      position: _position,
      duration: _number(_state['duration']),
    );
    if (position == null || !mounted) return;
    if (!_connected ||
        _state['seekable'] != true ||
        _text(_track['path']) != path) {
      _notice('The playing track changed. Open Jump to time again.');
      return;
    }
    await _run('seek.absolute', {'value': position});
  }

  Widget _seekBar(double position, double duration) => Row(
    children: [
      SizedBox(
        width: 42,
        child: Tooltip(
          message: 'Jump to time',
          child: InkWell(
            onTap: _connected && _state['seekable'] == true
                ? _jumpToTime
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _duration(position),
                textAlign: TextAlign.right,
                style: TextStyle(color: _muted, fontSize: 10),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            // Flutter reparents a slider's internal global key when its focus
            // shortcuts change on enable/disable. Recreate that local subtree
            // so the accessibility geometry cannot retain the former parent.
            key: ValueKey(('seek', _connected && _state['seekable'] == true)),
            value: position.clamp(0, math.max(duration, 1)),
            min: 0,
            max: math.max(duration, 1),
            onChanged: _connected && _state['seekable'] == true
                ? (value) => setState(() => _seekPreview = value)
                : null,
            onChangeEnd: (value) async {
              await _run('seek.absolute', {'value': value});
              if (mounted) setState(() => _seekPreview = null);
            },
            semanticFormatterCallback: _duration,
          ),
        ),
      ),
      SizedBox(
        width: 42,
        child: Text(
          _track['realtime'] == true ? 'LIVE' : _duration(duration),
          style: TextStyle(color: _muted, fontSize: 10),
        ),
      ),
    ],
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.track,
    this.icon = Icons.music_note_rounded,
    this.large = false,
  });
  final Json track;
  final IconData icon;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final art = _text(track['album_art_url']);
    final seed = _text(
      track['title'],
      _text(track['path'], 'cliamp'),
    ).codeUnits.fold(0, (a, b) => a + b);
    final colors = [
      [const Color(0xff326b63), const Color(0xff253044)],
      [const Color(0xff675087), const Color(0xff293345)],
      [const Color(0xff86614c), const Color(0xff3e344c)],
      [const Color(0xff315b7e), const Color(0xff35444c)],
    ][seed % 4];
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (large)
            Positioned(
              right: -20,
              top: -22,
              child: Container(
                width: 115,
                height: 115,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .07),
                    width: 20,
                  ),
                ),
              ),
            ),
          Icon(
            icon,
            color: Colors.white.withValues(alpha: .65),
            size: large ? 46 : 21,
          ),
        ],
      ),
    );
    Widget image = fallback;
    final uri = Uri.tryParse(art);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      image = Image.network(
        art,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (uri != null && uri.scheme == 'file') {
      try {
        image = Image.file(
          File.fromUri(uri),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
      } on ArgumentError {
        image = fallback;
      } on UnsupportedError {
        image = fallback;
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(large ? 12 : 7),
      child: image,
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter(
    this.bands, {
    required this.playing,
    required this.accent,
    required this.secondary,
  });
  final Color accent, secondary;
  final List<double> bands;
  final bool playing;
  @override
  void paint(Canvas canvas, Size size) {
    const count = 40;
    final barWidth = size.width / count;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [accent, secondary],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Offset.zero & size);
    for (var i = 0; i < count; i++) {
      final value = bands.isEmpty || !playing
          ? 0.0
          : bands[(i * bands.length ~/ count).clamp(0, bands.length - 1)].clamp(
              0.0,
              1.0,
            );
      final height = math.max(2.0, value * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * barWidth,
            (size.height - height) / 2,
            math.max(1.0, barWidth - 3),
            height,
          ),
          const Radius.circular(3),
        ),
        paint..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.playing != playing ||
      oldDelegate.accent != accent ||
      oldDelegate.secondary != secondary;
}

class _BandSlider extends StatefulWidget {
  const _BandSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;
  @override
  State<_BandSlider> createState() => _BandSliderState();
}

class _BandSliderState extends State<_BandSlider> {
  double? _preview;
  @override
  Widget build(BuildContext context) => RotatedBox(
    quarterTurns: 3,
    child: Slider(
      value: (_preview ?? widget.value).clamp(-12.0, 12.0),
      min: -12,
      max: 12,
      divisions: 24,
      label: '${(_preview ?? widget.value).round()} dB',
      onChanged: (value) => setState(() => _preview = value),
      onChangeEnd: (value) {
        widget.onChanged(value);
        setState(() => _preview = null);
      },
    ),
  );
}

/// The route may remain mounted while it animates out after Navigator.pop.
/// Keep editable resources alive until Flutter disposes that subtree.
Future<T?> _showInputDialog<T>({
  required BuildContext context,
  String initial = '',
  required Widget Function(BuildContext, TextEditingController) builder,
}) => showDialog<T>(
  context: context,
  builder: (_) => _DialogInput(initial: initial, builder: builder),
);

class _DialogInput extends StatefulWidget {
  const _DialogInput({required this.initial, required this.builder});
  final String initial;
  final Widget Function(BuildContext, TextEditingController) builder;
  @override
  State<_DialogInput> createState() => _DialogInputState();
}

class _DialogInputState extends State<_DialogInput> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
