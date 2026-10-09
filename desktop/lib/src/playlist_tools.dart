import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'backend.dart';

/// Saved-playlist edits use the engine's document-preserving operations.
class PlaylistToolsDialog extends StatefulWidget {
  const PlaylistToolsDialog({
    super.key,
    required this.backend,
    required this.provider,
    required this.playlist,
    this.onChanged,
  });
  final PlayerBackend backend;
  final String provider;
  final String playlist;
  final VoidCallback? onChanged;

  @override
  State<PlaylistToolsDialog> createState() => _PlaylistToolsDialogState();
}

class _PlaylistToolsDialogState extends State<PlaylistToolsDialog> {
  Map<String, dynamic> _capabilities = {};
  List<Map<String, dynamic>> _directories = [];
  List<Map<String, dynamic>> _tracks = [];
  String? _error;
  bool _busy = true;
  bool _changed = false;
  String _sort = 'title';
  int _pageOffset = 0;
  int _total = 0;

  Map<String, dynamic> get _target => {
    'provider': widget.provider,
    'playlist': widget.playlist,
  };
  List<Map<String, dynamic>> _objects(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _busy = true);
    try {
      final capabilities = await widget.backend.call(
        'playlist.capabilities',
        _target,
      );
      final dirs = capabilities['directories'] == true
          ? await widget.backend.call('playlist.dirs.list', _target)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities;
        _directories = _objects(dirs['directories']);
        _error = null;
      });
      final page = capabilities['replace'] == true
          ? await widget.backend.call('provider.tracks', {
              ..._target,
              'offset': _pageOffset,
              'limit': 200,
            })
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _tracks = _objects(page['tracks']);
          _total = (page['total'] as num?)?.toInt() ?? _tracks.length;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.call(operation, {..._target, ...params});
      _changed = true;
      widget.onChanged?.call();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addDirectory() async {
    try {
      final path = await getDirectoryPath(
        confirmButtonText: 'Add directory source',
      );
      if (path != null && mounted) {
        await _write('playlist.dirs.add', {'path': path});
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _addFiles() async {
    try {
      final files = await openFiles(confirmButtonText: 'Add to playlist');
      if (files.isNotEmpty && mounted) {
        await _write('playlist.import', {
          'args': files.map((file) => file.path).toList(),
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _removeDirectory(Map<String, dynamic> source) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove directory source?'),
        content: Text(
          '${source['path']}\n\nThe files stay on disk. '
          'They will no longer be supplied by this playlist source.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove source'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _write('playlist.dirs.remove', {'path': source['path']});
    }
  }

  Future<void> _sortTracks() async {
    _pageOffset = 0;
    await _write('playlist.sort', {'sort': _sort});
  }

  Future<void> _moveTrack(int from, int step) async {
    var to = from + step;
    while (to >= 0 &&
        to < _tracks.length &&
        _tracks[to]['dir_sourced'] == true) {
      to += step;
    }
    final target = _pageOffset + to;
    if (target < 0 || target >= _total) return;
    await _write('playlist.move', {
      'index': _pageOffset + from,
      'to': target,
      'track': _tracks[from],
    });
  }

  void _changePage(int direction) {
    setState(
      () => _pageOffset = (_pageOffset + 200 * direction).clamp(0, _total),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Manage ${widget.playlist}'),
    content: SizedBox(
      width: 720,
      height: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_capabilities['import'] == true &&
              _capabilities['can_add'] != false)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : _addFiles,
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('Add files'),
              ),
            ),
          if (_capabilities['directories'] == true) ...[
            Row(
              children: [
                const Expanded(child: Text('Directory sources')),
                TextButton.icon(
                  onPressed: _busy ? null : _addDirectory,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add folder'),
                ),
              ],
            ),
            if (_directories.isEmpty)
              const Text('No directory sources. Added folders rescan on load.'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 155),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final source in _directories)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text('${source['path']}'),
                      subtitle: const Text('Include subfolders'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: source['recursive'] == true,
                            onChanged: _busy
                                ? null
                                : (enabled) =>
                                      _write('playlist.dirs.recursive', {
                                        'path': source['path'],
                                        'name': enabled ? 'on' : 'off',
                                      }),
                          ),
                          IconButton(
                            tooltip: 'Remove directory source',
                            onPressed: _busy
                                ? null
                                : () => _removeDirectory(source),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
          ],
          if (_capabilities['replace'] == true) ...[
            Row(
              children: [
                Expanded(child: Text('$_total tracks')),
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(
                      value: 'track',
                      child: Text('Track number'),
                    ),
                    DropdownMenuItem(value: 'title', child: Text('Title')),
                    DropdownMenuItem(value: 'artist', child: Text('Artist')),
                    DropdownMenuItem(value: 'album', child: Text('Album')),
                    DropdownMenuItem(
                      value: 'artist+album',
                      child: Text('Artist + album'),
                    ),
                    DropdownMenuItem(value: 'path', child: Text('Path')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _sort = value ?? 'title'),
                ),
                TextButton.icon(
                  onPressed: _busy || _tracks.isEmpty ? null : _sortTracks,
                  icon: const Icon(Icons.sort),
                  label: const Text('Sort and save'),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _tracks.length,
                itemBuilder: (context, index) {
                  final track = _tracks[index];
                  final sourced = track['dir_sourced'] == true;
                  return ListTile(
                    dense: true,
                    leading: sourced
                        ? const Tooltip(
                            message: 'Supplied by a directory source',
                            child: Icon(Icons.folder_outlined),
                          )
                        : Text('${_pageOffset + index + 1}'),
                    title: Text('${track['title'] ?? track['path']}'),
                    subtitle: Text('${track['artist'] ?? ''}'),
                    trailing: sourced
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Move track up',
                                onPressed: _busy || _pageOffset + index == 0
                                    ? null
                                    : () => _moveTrack(index, -1),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: 'Move track down',
                                onPressed:
                                    _busy || _pageOffset + index == _total - 1
                                    ? null
                                    : () => _moveTrack(index, 1),
                                icon: const Icon(Icons.arrow_downward),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${_total == 0 ? 0 : _pageOffset + 1}–${_pageOffset + _tracks.length} of $_total',
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _busy || _pageOffset == 0
                      ? null
                      : () => _changePage(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _busy || _pageOffset + _tracks.length >= _total
                      ? null
                      : () => _changePage(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ] else
            const Expanded(
              child: Center(
                child: Text('This provider does not support playlist sorting.'),
              ),
            ),
        ],
      ),
    ),
    actions: [
      if (_capabilities['undo'] == true)
        TextButton.icon(
          onPressed: _busy ? null : () => _write('playlist.undo'),
          icon: const Icon(Icons.undo),
          label: const Text('Undo last playlist edit'),
        ),
      TextButton(
        onPressed: _busy ? null : _refresh,
        child: const Text('Refresh'),
      ),
      FilledButton(
        onPressed: _busy ? null : () => Navigator.pop(context, _changed),
        child: const Text('Done'),
      ),
    ],
  );
}
