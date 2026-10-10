import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend.dart';

/// Renders the engine's own visualizers, including installed Lua visualizers.
/// The terminal frames retain their exact colors and spacing in Flutter.
class EngineVisualizer extends StatefulWidget {
  const EngineVisualizer({
    super.key,
    required this.backend,
    required this.operations,
    required this.onError,
    this.onCleanupReady,
    this.playbackState = const {},
  });
  final PlayerBackend backend;
  final Map<String, dynamic> playbackState;
  final List<Map<String, dynamic>> operations;
  final ValueChanged<String> onError;
  final void Function(Future<void> Function())? onCleanupReady;
  @override
  State<EngineVisualizer> createState() => _EngineVisualizerState();
}

class _EngineVisualizerState extends State<EngineVisualizer> {
  Timer? _timer;
  late Map<String, dynamic> _playback = Map.of(widget.playbackState);
  bool _showTrackInfo = true;
  bool _transportBusy = false;
  String? _playbackError;
  bool _hasOperation(String operation) =>
      widget.operations.any((item) => item['name'] == operation);
  bool get _playing => _playback['state'] == 'playing';
  double get _volume => (_playback['volume'] as num?)?.toDouble() ?? 0;

  @override
  void didUpdateWidget(covariant EngineVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playbackState, widget.playbackState)) {
      _playback = Map.of(widget.playbackState);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _frameRevision.value++;
      });
    }
  }

  void _toggleTrackInfo() {
    setState(() => _showTrackInfo = !_showTrackInfo);
    _frameRevision.value++;
  }

  Future<void> _transport(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_transportBusy || !_hasOperation(operation)) return;
    if (operation == 'seek' && _playback['seekable'] != true) return;
    setState(() {
      _transportBusy = true;
      _playbackError = null;
    });
    _frameRevision.value++;
    try {
      final result = await widget.backend.call(operation, params);
      if (result['ok'] == false) {
        throw BackendException(
          '${result['error'] ?? 'Playback command failed.'}',
        );
      }
      final state = await widget.backend.snapshot();
      if (mounted && state.isNotEmpty) setState(() => _playback = state);
    } catch (error) {
      if (mounted) setState(() => _playbackError = '$error');
      widget.onError('$error');
    } finally {
      if (mounted) {
        setState(() => _transportBusy = false);
        _frameRevision.value++;
      }
    }
  }

  bool _loading = false;
  String _frame = '';
  String _mode = '';
  int? _modeIndex;
  String _theme = '';
  String? _error;
  List<String> _modes = [];
  List<String> _themes = [];
  final _frameRevision = ValueNotifier(0);
  Future<void> _appearanceWork = Future.value();
  Future<void>? _restoration;
  int? _originalMode;
  String? _originalTheme;
  bool _changing = false;
  Color _background = const Color(0xff0b0d12);
  Color _foreground = Colors.white;
  bool get _previewing => _originalMode != null;
  bool get _previewSupported =>
      widget.operations.any((o) => o['name'] == 'desktop.theme.preview') &&
      widget.operations.any((o) => o['name'] == 'desktop.vis.preview');
  bool get _supported =>
      widget.operations.any((o) => o['name'] == 'desktop.vis.frame');

  @override
  void initState() {
    super.initState();
    widget.onCleanupReady?.call(_restorePreview);
    if (_supported) _start();
  }

  Future<void> _start() async {
    _timer?.cancel();
    try {
      final results = await Future.wait([
        widget.backend.call('desktop.vis', {'name': 'list'}),
        widget.backend.call('desktop.theme', {'name': 'list'}),
      ]);
      if (!mounted) return;
      setState(() {
        _modes = (results[0]['items'] as List? ?? [])
            .map((value) => '$value')
            .toList();
        _modeIndex = (results[0]['index'] as num?)?.toInt() ?? 0;
        _themes = (results[1]['items'] as List? ?? [])
            .map((value) => '$value')
            .toList();
      });
      await _refresh();
      if (mounted) {
        _timer = Timer.periodic(
          Duration(
            milliseconds: widget.backend is VisualizerFrameBackend ? 67 : 400,
          ),
          (_) => _refresh(),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      final backend = widget.backend;
      final result = backend is VisualizerFrameBackend
          ? await (backend as VisualizerFrameBackend).readFrame(80, 24)
          : await backend.call('desktop.vis.frame', {
              'width': 80,
              'height': 24,
            });
      if (mounted) {
        setState(() {
          _frame = result['frame'] as String? ?? '';
          _mode = result['visualizer'] as String? ?? _mode;
          _modeIndex = (result['index'] as num?)?.toInt() ?? 0;
          final theme = result['theme'];
          _theme = theme is Map ? '${theme['name'] ?? ''}' : '$theme';
          if (theme is Map) {
            _background = _color(theme['bg'], const Color(0xff0b0d12));
            _foreground = _color(theme['fg'], Colors.white);
          }
          _error = null;
        });
        _frameRevision.value++;
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      _timer?.cancel();
    } finally {
      _loading = false;
    }
  }

  Future<void> _select(String operation, Map<String, dynamic> params) async {
    if (_changing || _theme.isEmpty || _modeIndex == null) return;
    if (_previewSupported && !_previewing) {
      _originalMode = _modeIndex ?? 0;
      _originalTheme = _theme;
    }
    if (operation == 'desktop.vis' && params['name'] == 'next') {
      params = {
        'index': ((_modeIndex ?? 0) + 1) % (_modes.isEmpty ? 1 : _modes.length),
      };
    }
    setState(() => _changing = true);
    try {
      final requestedOperation = _previewSupported
          ? '$operation.preview'
          : operation;
      _appearanceWork = _appearanceWork.then((_) async {
        final result = await widget.backend.call(requestedOperation, params);
        if (operation == 'desktop.vis' && mounted) {
          setState(() => _modeIndex = (result['index'] as num?)?.toInt() ?? 0);
        }
      });
      await _appearanceWork;
      await _refresh();
    } catch (error) {
      _appearanceWork = Future.value();
      widget.onError('$error');
    } finally {
      if (mounted) {
        setState(() => _changing = false);
        _frameRevision.value++;
      }
    }
  }

  Color _color(dynamic value, Color fallback) {
    final hex = '$value'.replaceFirst('#', '');
    if (hex.length != 6) return fallback;
    final number = int.tryParse(hex, radix: 16);
    return number == null ? fallback : Color(0xff000000 | number);
  }

  Future<void> _restorePreview() => _restoration ??= _restoreOriginal()
      .whenComplete(() => _restoration = null);

  Future<void> _restoreOriginal() async {
    await _appearanceWork.catchError((_) {});
    final mode = _originalMode;
    final theme = _originalTheme;
    if (mode == null) return;
    await widget.backend.call('desktop.vis.preview', {'index': mode});
    if (theme != null && theme.isNotEmpty) {
      await widget.backend.call('desktop.theme.preview', {'name': theme});
    }
    _originalMode = null;
    _originalTheme = null;
  }

  Future<void> _cancelPreview() async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      await _restorePreview();
      await _refresh();
    } catch (error) {
      _appearanceWork = Future.value();
      widget.onError('$error');
    } finally {
      if (mounted) {
        setState(() => _changing = false);
        _frameRevision.value++;
      }
    }
  }

  Future<void> _applyPreview() async {
    if (_changing || !_previewing) return;
    setState(() => _changing = true);
    try {
      _appearanceWork = _appearanceWork.then((_) async {
        await widget.backend.call('desktop.vis', {'index': _modeIndex ?? 0});
        await widget.backend.call('desktop.theme', {'name': _theme});
        _originalMode = null;
        _originalTheme = null;
      });
      await _appearanceWork;
      await _refresh();
    } catch (error) {
      _appearanceWork = Future.value();
      widget.onError('$error');
    } finally {
      if (mounted) {
        setState(() => _changing = false);
        _frameRevision.value++;
      }
    }
  }

  Widget _canvas() => ColoredBox(
    color: _background,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text.rich(
            TextSpan(children: ansiSpans(_frame)),
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Courier New', 'DejaVu Sans Mono'],
              fontSize: 12,
              height: 1.15,
              color: _foreground,
            ),
            softWrap: false,
          ),
        ),
      ),
    ),
  );

  List<Widget> _previewActions() => [
    if (_previewing) ...[
      TextButton(
        onPressed: _changing ? null : _cancelPreview,
        child: const Text('Cancel preview'),
      ),
      FilledButton(
        onPressed: _changing ? null : _applyPreview,
        child: const Text('Apply appearance'),
      ),
    ],
  ];

  Widget _transportButton(
    String label,
    IconData icon,
    String operation, [
    Map<String, dynamic> params = const {},
  ]) => IconButton(
    tooltip: label,
    onPressed:
        _transportBusy ||
            !_hasOperation(operation) ||
            (operation == 'seek' && _playback['seekable'] != true)
        ? null
        : () => _transport(operation, params),
    icon: Icon(icon),
  );

  Widget _fullscreenPlayer() {
    final rawTrack = _playback['track'];
    final track = rawTrack is Map ? rawTrack : const <String, dynamic>{};
    final title = '${track['title'] ?? track['path'] ?? 'Nothing playing'}';
    final detail = [
      track['artist'],
      track['album'],
    ].where((value) => value != null && '$value'.isNotEmpty).join(' · ');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showTrackInfo) ...[
                Text(
                  title,
                  key: const ValueKey('fullscreen-track-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  _transportButton(
                    'Previous track (,)',
                    Icons.skip_previous_rounded,
                    'prev',
                  ),
                  _transportButton(
                    'Seek back 5 seconds (Left)',
                    Icons.replay_5_rounded,
                    'seek',
                    {'value': -5},
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _transportBusy || !_hasOperation('toggle')
                        ? null
                        : () => _transport('toggle'),
                    icon: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(_playing ? 'Pause' : 'Play'),
                  ),
                  _transportButton(
                    'Seek forward 5 seconds (Right)',
                    Icons.forward_5_rounded,
                    'seek',
                    {'value': 5},
                  ),
                  _transportButton(
                    'Next track (.)',
                    Icons.skip_next_rounded,
                    'next',
                  ),
                  const SizedBox(width: 16),
                  _transportButton(
                    'Lower volume (-)',
                    Icons.volume_down_rounded,
                    'volume.adjust',
                    {'value': -1},
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${_volume.toStringAsFixed(0)} dB',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  _transportButton(
                    'Raise volume (+)',
                    Icons.volume_up_rounded,
                    'volume.adjust',
                    {'value': 1},
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Space: play / pause · T: track information · V: visualizer · Esc: exit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_playbackError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _playbackError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fullscreen() => showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(dialogContext),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _transport('toggle'),
        const SingleActivator(LogicalKeyboardKey.comma): () =>
            _transport('prev'),
        const SingleActivator(LogicalKeyboardKey.period): () =>
            _transport('next'),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
        ): () =>
            _transport('prev'),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ): () =>
            _transport('next'),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            _transport('prev'),
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            _transport('next'),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _transport('seek', {'value': -5}),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _transport('seek', {'value': 5}),
        const SingleActivator(LogicalKeyboardKey.minus): () =>
            _transport('volume.adjust', {'value': -1}),
        const SingleActivator(LogicalKeyboardKey.equal): () =>
            _transport('volume.adjust', {'value': 1}),
        const SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
            _transport('volume.adjust', {'value': 1}),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
            _transport('volume.adjust', {'value': 1}),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
            _transport('volume.adjust', {'value': -1}),
        const SingleActivator(LogicalKeyboardKey.keyT): _toggleTrackInfo,
        const SingleActivator(LogicalKeyboardKey.keyV): () =>
            _select('desktop.vis', {'name': 'next'}),
      },
      child: FocusScope(
        autofocus: true,
        child: Dialog.fullscreen(
          backgroundColor: _background,
          child: ValueListenableBuilder<int>(
            valueListenable: _frameRevision,
            builder: (context, _, _) => Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 16, 12),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text('$_mode · $_theme'),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ..._previewActions(),
                              IconButton(
                                tooltip: _showTrackInfo
                                    ? 'Hide track information (T)'
                                    : 'Show track information (T)',
                                onPressed: _toggleTrackInfo,
                                icon: Icon(
                                  _showTrackInfo
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next visualizer',
                                onPressed: _changing
                                    ? null
                                    : () => _select('desktop.vis', {
                                        'name': 'next',
                                      }),
                                icon: const Icon(Icons.graphic_eq_rounded),
                              ),
                              IconButton(
                                tooltip: 'Exit fullscreen visualizer',
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.fullscreen_exit),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: _canvas()),
                _fullscreenPlayer(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_restorePreview().catchError((_) {}));
    _frameRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: SizedBox(
        height: constraints.maxHeight < 500 ? 500 : constraints.maxHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 14, 32, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'See what you hear.',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Original Cliamp visualizers, including your Lua extensions.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
              if (!_supported)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Visualizers require the desktop-enabled Cliamp engine.',
                    ),
                  ),
                )
              else ...[
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(_modeIndex),
                        initialValue:
                            _modeIndex != null &&
                                _modeIndex! >= 0 &&
                                _modeIndex! < _modes.length
                            ? _modeIndex
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Visualizer',
                        ),
                        items: _modes
                            .asMap()
                            .entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _changing
                            ? null
                            : (value) {
                                if (value != null) {
                                  _select('desktop.vis', {'index': value});
                                }
                              },
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_theme),
                        initialValue: _themes.contains(_theme) ? _theme : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Theme'),
                        items: _themes
                            .toSet()
                            .map(
                              (theme) => DropdownMenuItem(
                                value: theme,
                                child: Text(
                                  theme,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _changing
                            ? null
                            : (value) {
                                if (value != null) {
                                  _select('desktop.theme', {'name': value});
                                }
                              },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next visualizer',
                      onPressed: _changing
                          ? null
                          : () => _select('desktop.vis', {'name': 'next'}),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    IconButton(
                      tooltip: 'Enter fullscreen visualizer',
                      onPressed: _fullscreen,
                      icon: const Icon(Icons.fullscreen),
                    ),
                    ..._previewActions(),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: _background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: .06),
                      ),
                    ),
                    child: _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 15),
                                  TextButton(
                                    onPressed: _start,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _canvas(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _mode.isEmpty
                      ? 'Start a track to bring your music to life.'
                      : '$_mode · $_theme',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

const _ansiColors = [
  Color(0xff000000),
  Color(0xffcc4444),
  Color(0xff44bb77),
  Color(0xffddbb55),
  Color(0xff5577dd),
  Color(0xffbb66cc),
  Color(0xff55bbbb),
  Color(0xffdddddd),
  Color(0xff777777),
  Color(0xffff6666),
  Color(0xff77ee99),
  Color(0xffffee88),
  Color(0xff88aaff),
  Color(0xffee99ff),
  Color(0xff88eeee),
  Color(0xffffffff),
];

Color _ansiColor(int code) {
  if (code < 16) return _ansiColors[code.clamp(0, 15)];
  if (code >= 232) {
    final gray = (8 + (code - 232) * 10).clamp(0, 255);
    return Color.fromARGB(255, gray, gray, gray);
  }
  final value = code - 16;
  int channel(int n) => n == 0 ? 0 : 55 + n * 40;
  return Color.fromARGB(
    255,
    channel(value ~/ 36),
    channel((value ~/ 6) % 6),
    channel(value % 6),
  );
}

/// ANSI styling is parsed as text; no escape sequence is executed by the UI.
List<TextSpan> ansiSpans(String input) {
  final spans = <TextSpan>[];
  final pattern = RegExp(r'\x1b\[[0-9;:?]*[ -/]*[@-~]');
  Color? foreground;
  Color? background;
  bool bold = false;
  var cursor = 0;
  void add(String text) {
    if (text.isNotEmpty) {
      spans.add(
        TextSpan(
          text: text,
          style: TextStyle(
            color: foreground,
            backgroundColor: background,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }
  }

  for (final match in pattern.allMatches(input)) {
    add(input.substring(cursor, match.start));
    cursor = match.end;
    final sequence = match.group(0)!;
    if (!sequence.endsWith('m')) continue;
    final params = sequence
        .substring(2, sequence.length - 1)
        .split(';')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    for (var i = 0; i < params.length; i++) {
      final value = params[i];
      if (value == 0) {
        foreground = null;
        background = null;
        bold = false;
      } else if (value == 1) {
        bold = true;
      } else if (value == 22) {
        bold = false;
      } else if (value == 39) {
        foreground = null;
      } else if (value == 49) {
        background = null;
      } else if (value >= 30 && value <= 37) {
        foreground = _ansiColors[value - 30];
      } else if (value >= 90 && value <= 97) {
        foreground = _ansiColors[value - 90 + 8];
      } else if (value >= 40 && value <= 47) {
        background = _ansiColors[value - 40];
      } else if (value >= 100 && value <= 107) {
        background = _ansiColors[value - 100 + 8];
      } else if ((value == 38 || value == 48) && i + 2 < params.length) {
        Color? color;
        if (params[i + 1] == 5) {
          color = _ansiColor(params[i + 2].clamp(0, 255));
          i += 2;
        } else if (params[i + 1] == 2 && i + 4 < params.length) {
          color = Color.fromARGB(
            255,
            params[i + 2].clamp(0, 255),
            params[i + 3].clamp(0, 255),
            params[i + 4].clamp(0, 255),
          );
          i += 4;
        }
        if (value == 38) {
          foreground = color;
        } else {
          background = color;
        }
      }
    }
  }
  add(input.substring(cursor));
  return spans;
}
