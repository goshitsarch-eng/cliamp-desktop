import 'package:flutter/material.dart';

import 'backend.dart';

/// Uses the engine's existing setup schema and credential store. Secret values
/// stay in editable fields and are sent by the adapter over stdin only.
class ProviderSetupDialog extends StatefulWidget {
  const ProviderSetupDialog({super.key, required this.backend});
  final ProviderSetupBackend backend;
  @override
  State<ProviderSetupDialog> createState() => _ProviderSetupDialogState();
}

class _ProviderSetupDialogState extends State<ProviderSetupDialog> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  Map<String, dynamic> _schema = {};
  List<Map<String, dynamic>> _providers = [];
  Map<String, String> _values = {};
  String _provider = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  bool _saveFailed = false;
  int _generation = 0;

  List<Map<String, dynamic>> _objects(dynamic data) => data is List
      ? data
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
      : [];

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.backend.setupSchema(_provider, _values);
      if (!mounted || generation != _generation) return;
      setState(() {
        _schema = result;
        final providers = _objects(result['providers']);
        if (providers.isNotEmpty) _providers = providers;
        final defaults = result['values'];
        if (defaults is Map) {
          for (final entry in defaults.entries) {
            _values.putIfAbsent('${entry.key}', () => '${entry.value}');
          }
        }
        for (final field in _objects(result['fields'])) {
          final key = '${field['key']}';
          _controllers.putIfAbsent(
            key,
            () => TextEditingController(
              text: _values[key] ?? '${field['value'] ?? ''}',
            ),
          );
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  void _readFields() {
    for (final field in _objects(_schema['fields'])) {
      final key = '${field['key']}';
      _values[key] = _controllers[key]?.text ?? '';
    }
  }

  Future<void> _chooseProvider(String provider) async {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    setState(() {
      _provider = provider;
      _values = {};
      _schema = {};
    });
    await _loadSchema();
  }

  Future<void> _save({bool verifyConnection = true}) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    _readFields();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.backend.saveProvider(
        _provider,
        _values,
        verifyConnection: verifyConnection,
      );
      if (result['ok'] == false) {
        throw const FormatException(
          'Unable to save this provider. Check the account details.',
        );
      }
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _restart() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.backend.restartOwnedEngine();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picker = _schema['picker'];
    final pickerMap = picker is Map
        ? Map<String, dynamic>.from(picker)
        : <String, dynamic>{};
    final options = _objects(pickerMap['options']);
    final pickerKey = '${pickerMap['key'] ?? ''}';
    final pickerValue = _values[pickerKey];
    final fields = _objects(_schema['fields']);
    return AlertDialog(
      title: Text(
        _saved ? 'Your provider is configured' : 'Connect your music',
      ),
      scrollable: true,
      content: SizedBox(
        width: 540,
        child: _saved
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xff81e6cd),
                    size: 36,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Your account settings have been saved in Cliamp’s credential store.',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.backend.ownsDaemon
                        ? 'Restart the player to load the provider. This stops current playback.'
                        : 'This app is connected to an existing Cliamp player. Restart that player, then reconnect this app to load the provider.',
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(),
                  ],
                  if (_error != null) _errorMessage(),
                ],
              )
            : Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Choose a service and enter its connection details. Your existing library and player preferences are preserved.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue:
                          _providers.any(
                            (provider) => provider['key'] == _provider,
                          )
                          ? _provider
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Music service',
                      ),
                      isExpanded: true,
                      items: _providers
                          .map(
                            (provider) => DropdownMenuItem(
                              value: '${provider['key']}',
                              child: Text('${provider['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) _chooseProvider(value);
                            },
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 20),
                      const LinearProgressIndicator(),
                    ],
                    if (!_loading && _provider.isNotEmpty) ...[
                      if ('${_schema['intro'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          _schema['intro'] is List
                              ? (_schema['intro'] as List).join('\n')
                              : '${_schema['intro']}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (options.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          key: ValueKey('$_provider:$pickerKey'),
                          initialValue:
                              options.any(
                                (option) => '${option['value']}' == pickerValue,
                              )
                              ? pickerValue
                              : '${options.first['value']}',
                          decoration: InputDecoration(
                            labelText:
                                '${pickerMap['label'] ?? 'Connection type'}',
                          ),
                          isExpanded: true,
                          items: options
                              .map(
                                (option) => DropdownMenuItem(
                                  value: '${option['value']}',
                                  child: Text('${option['label']}'),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _readFields();
                                    _values[pickerKey] = value;
                                    _loadSchema();
                                  }
                                },
                        ),
                      ],
                      for (final field in fields) ...[
                        const SizedBox(height: 20),
                        TextFormField(
                          key: ValueKey('$_provider:${field['key']}'),
                          controller: _controllers['${field['key']}'],
                          enabled: !_saving,
                          obscureText: field['secret'] == true,
                          enableSuggestions: field['secret'] != true,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText:
                                '${field['label']}${field['required'] == true ? ' *' : ''}',
                            helperText: '${field['help'] ?? ''}'.isEmpty
                                ? null
                                : '${field['help']}',
                            helperMaxLines: 4,
                          ),
                          validator: (value) =>
                              field['required'] == true &&
                                  (value?.trim().isEmpty ?? true)
                              ? 'This field is required.'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Saving replaces this provider’s connection details and credentials. Existing secrets are never shown here; enter the credentials you want to use.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          height: 1.6,
                        ),
                      ),
                    ],
                    if (_error != null) _errorMessage(),
                    if (_saving) ...[
                      const SizedBox(height: 20),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(_saved ? 'Later' : 'Cancel'),
        ),
        if (_saved && widget.backend.ownsDaemon)
          FilledButton(
            onPressed: _saving ? null : _restart,
            child: const Text('Restart player'),
          ),
        if (!_saved && _saveFailed)
          TextButton(
            onPressed: _loading || _saving
                ? null
                : () => _save(verifyConnection: false),
            child: const Text('Save without connection check'),
          ),
        if (!_saved)
          FilledButton(
            onPressed: _provider.isEmpty || _loading || _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save provider'),
          ),
      ],
    );
  }

  Widget _errorMessage() => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Text(
      _error!,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 12,
      ),
    ),
  );
}
