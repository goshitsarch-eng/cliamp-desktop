import 'package:flutter/material.dart';

import 'backend.dart';

/// Plugin approvals are tied to the source, hash and permissions displayed in
/// a separate review. The CLI rejects stale or changed reviews.
class PluginManagerDialog extends StatefulWidget {
  const PluginManagerDialog({super.key, required this.backend});
  final DesktopManagementBackend backend;

  @override
  State<PluginManagerDialog> createState() => _PluginManagerDialogState();
}

class _PluginManagerDialogState extends State<PluginManagerDialog> {
  final _source = TextEditingController();
  List<Map<String, dynamic>> _plugins = [];
  String? _error;
  bool _busy = true;
  bool _changed = false;
  bool _reviewOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.backend.pluginAction('list');
      if (!mounted) return;
      setState(() {
        _plugins = (result['plugins'] as List? ?? [])
            .whereType<Map>()
            .map((plugin) => Map<String, dynamic>.from(plugin))
            .toList();
        _error = result['warning'] as String?;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _review({String? name}) async {
    if (name == null && _source.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.backend.pluginAction(
        name == null ? 'prepare' : 'review',
        name == null ? {'source': _source.text.trim()} : {'name': name},
      );
      if (!mounted) return;
      final review = Map<String, dynamic>.from(result['review'] as Map);
      setState(() => _reviewOpen = true);
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _PluginReviewDialog(backend: widget.backend, review: review),
      );
      if (!mounted) return;
      setState(() => _reviewOpen = false);
      if (approved == true) {
        _changed = true;
        if (name == null) _source.clear();
      }
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _configure(Map<String, dynamic> plugin) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _PluginConfigurationDialog(plugin: plugin),
    );
    if (values == null || !mounted) return;
    await _change('configure', {'name': plugin['id'], 'values': values});
  }

  Future<void> _remove(Map<String, dynamic> plugin) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${plugin['name']}?'),
        content: const Text(
          'The installed plugin files and its approval will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true && mounted) {
      await _change('remove', {'name': plugin['id']});
    }
  }

  Future<void> _change(String action, Map<String, dynamic> values) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.pluginAction(action, values);
      _changed = true;
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _restart() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.restartOwnedEngine();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Plugins'),
    content: SizedBox(
      width: 740,
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _source,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Plugin source',
                    hintText: 'owner/cliamp-plugin-name or HTTPS URL',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _review(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _busy ? null : () => _review(),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review source'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_busy && !_reviewOpen) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_changed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                widget.backend.ownsDaemon
                    ? 'Changes saved. Restart the player to reload plugins.'
                    : 'Changes saved. Restart the connected player to reload plugins.',
              ),
            ),
          Expanded(
            child: _plugins.isEmpty && !_busy
                ? const Center(
                    child: Text(
                      'Add a plugin source above to review and install it.',
                    ),
                  )
                : ListView.separated(
                    itemCount: _plugins.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final plugin = _plugins[index];
                      final enabled = plugin['enabled'] == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          plugin['trust'] == 'trusted'
                              ? Icons.verified_user_outlined
                              : Icons.shield_outlined,
                        ),
                        title: Text('${plugin['name']}'),
                        subtitle: Text(
                          '${plugin['version']} · ${plugin['type']} · ${plugin['trust']}\n${plugin['description']}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          requestFocus: true,
                          enabled: !_busy,
                          onSelected: (action) {
                            switch (action) {
                              case 'review':
                                _review(name: '${plugin['id']}');
                              case 'configure':
                                _configure(plugin);
                              case 'toggle':
                                _change('configure', {
                                  'name': plugin['id'],
                                  'values': {'enabled': '${!enabled}'},
                                });
                              case 'remove':
                                _remove(plugin);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'review',
                              child: Text('Review and trust content'),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(enabled ? 'Disable' : 'Enable'),
                            ),
                            const PopupMenuItem(
                              value: 'configure',
                              child: Text('Plugin settings'),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, _changed),
        child: const Text('Done'),
      ),
      if (_changed && widget.backend.ownsDaemon)
        FilledButton(
          onPressed: _busy ? null : _restart,
          child: const Text('Restart player'),
        ),
    ],
  );
}

class _PluginReviewDialog extends StatefulWidget {
  const _PluginReviewDialog({required this.backend, required this.review});
  final DesktopManagementBackend backend;
  final Map<String, dynamic> review;
  @override
  State<_PluginReviewDialog> createState() => _PluginReviewDialogState();
}

class _PluginReviewDialogState extends State<_PluginReviewDialog> {
  bool _approved = false;
  bool _busy = false;
  String? _error;

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final review = widget.review;
    try {
      await widget.backend.pluginAction(
        review['action'] == 'install' ? 'apply' : 'trust',
        {
          for (final key in ['token', 'source', 'sha256', 'permissions'])
            key: review[key],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final permissions = (review['permissions'] as List? ?? []).join(', ');
    return AlertDialog(
      title: Text('Review ${review['name']}'),
      content: SizedBox(
        width: 780,
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'Source: ${review['source']}\nSHA-256: ${review['sha256']}',
            ),
            const SizedBox(height: 10),
            Text(
              'Declared permissions: ${permissions.isEmpty ? 'none' : permissions}',
            ),
            Text('${review['implicit_access']}'),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    '${review['code']}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I approve this exact source, SHA-256 and permissions.',
              ),
              value: _approved,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _approved = value ?? false),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || !_approved ? null : _apply,
          child: Text(
            _busy
                ? 'Applying…'
                : review['action'] == 'install'
                ? 'Trust and install'
                : 'Trust this content',
          ),
        ),
      ],
    );
  }
}

class _PluginConfigurationDialog extends StatefulWidget {
  const _PluginConfigurationDialog({required this.plugin});
  final Map<String, dynamic> plugin;
  @override
  State<_PluginConfigurationDialog> createState() =>
      _PluginConfigurationDialogState();
}

class _PluginConfigurationDialogState
    extends State<_PluginConfigurationDialog> {
  final _key = TextEditingController();
  final _value = TextEditingController();
  final _changes = <String, String>{};
  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.plugin['name']} settings'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use the setting names documented by this plugin. Existing credential values stay hidden. An empty new value clears that setting.',
          ),
          const SizedBox(height: 12),
          Text(
            'Existing keys: ${(widget.plugin['config_keys'] as List? ?? []).join(', ')}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            decoration: const InputDecoration(labelText: 'Setting name'),
          ),
          TextField(
            controller: _value,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New value or environment reference',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                if (_key.text.trim().isEmpty) return;
                setState(() {
                  _changes[_key.text.trim()] = _value.text;
                  _key.clear();
                  _value.clear();
                });
              },
              child: const Text('Add change'),
            ),
          ),
          if (_changes.isNotEmpty)
            Text('Will update: ${_changes.keys.join(', ')}'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _changes.isEmpty
            ? null
            : () => Navigator.pop(context, _changes),
        child: const Text('Save settings'),
      ),
    ],
  );
}
