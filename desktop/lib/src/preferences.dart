import 'dart:convert';
import 'package:flutter/material.dart';

import 'backend.dart';

/// Edits the engine's persisted preferences from its bounded, nonsecret schema.
class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({super.key, required this.backend});
  final DesktopManagementBackend backend;

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  List<Map<String, dynamic>> _fields = [];
  final Map<String, String> _initial = {};
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  String _filter = '';
  String? _error;
  bool _busy = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final schema = await widget.backend.preferencesSchema();
      if (!mounted) return;
      setState(() {
        _fields = (schema['fields'] as List? ?? [])
            .whereType<Map>()
            .map((field) => Map<String, dynamic>.from(field))
            .toList();
        for (final field in _fields) {
          final key = '${field['key']}';
          final value = '${field['value'] ?? ''}';
          _initial[key] = value;
          _values[key] = value;
          _controllers[key] = TextEditingController(text: value);
        }
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  String? _validate(Map<String, dynamic> field, String value) {
    final type = field['type'];
    if (type == 'number' || type == 'integer') {
      final number = double.tryParse(value.trim());
      if (number == null ||
          !number.isFinite ||
          (type == 'integer' && number != number.truncateToDouble())) {
        return type == 'integer'
            ? 'Enter a whole number.'
            : 'Enter a finite number.';
      }
      final minimum = field['min'] as num?;
      final maximum = field['max'] as num?;
      if ((minimum != null && number < minimum) ||
          (maximum != null && number > maximum)) {
        return 'Value is outside the supported range ($minimum to $maximum).';
      }
    }
    if (type == 'list' || type == 'equalizer') {
      dynamic parsed;
      try {
        parsed = jsonDecode(value);
      } on FormatException {
        parsed = null;
      }
      if (type == 'list') {
        if (parsed is! List ||
            parsed.any(
              (item) =>
                  item is! String || item.contains('\n') || item.contains('\r'),
            )) {
          return 'Enter a JSON array of single-line names, such as ["First", "Second"].';
        }
      } else if (parsed is! List ||
          parsed.length != 10 ||
          parsed.any(
            (item) => item is! num || !item.isFinite || item < -12 || item > 12,
          )) {
        return 'Enter ten gains from -12 to 12 dB in a JSON array.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    for (final field in _fields) {
      final key = '${field['key']}';
      if (_values[key] == _initial[key]) continue;
      final error = _validate(field, _values[key] ?? '');
      if (error != null) {
        setState(() => _error = '${field['label']}: $error');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changed = <String, String>{
        for (final entry in _values.entries)
          if (_initial[entry.key] != entry.value) entry.key: entry.value,
      };
      final result = await widget.backend.savePreferences(changed);
      if (!mounted) return;
      setState(() {
        _initial.addAll(changed);
        _saved = _saved || result['restart_required'] == true;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
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
          _error = '$error';
          _busy = false;
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

  Widget _field(Map<String, dynamic> field) {
    final key = '${field['key']}';
    final label = '${field['label']}';
    final help = '${field['help'] ?? ''}';
    final value = _values[key] ?? '';
    if (field['type'] == 'bool') {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: help.isEmpty ? null : Text(help),
        value: value == 'true',
        onChanged: _busy
            ? null
            : (selected) => setState(() => _values[key] = '$selected'),
      );
    }
    final options = (field['options'] as List? ?? [])
        .map((item) => '$item')
        .toList();
    final bounds = field['min'] != null && field['max'] != null
        ? 'Range: ${field['min']} to ${field['max']}'
        : '';
    final decoration = InputDecoration(
      labelText: label,
      helperText:
          [help, bounds].where((part) => part.isNotEmpty).join('\n').isEmpty
          ? null
          : [help, bounds].where((part) => part.isNotEmpty).join('\n'),
      helperMaxLines: 3,
      border: const OutlineInputBorder(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: options.isNotEmpty
          ? DropdownButtonFormField<String>(
              key: ValueKey('$key:$value'),
              initialValue: value,
              decoration: decoration,
              isExpanded: true,
              items: {...options, value}
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(option.isEmpty ? 'Default' : option),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (selected) {
                      if (selected != null) {
                        setState(() => _values[key] = selected);
                      }
                    },
            )
          : TextField(
              controller: _controllers[key],
              enabled: !_busy,
              decoration: decoration,
              keyboardType:
                  field['type'] == 'number' || field['type'] == 'integer'
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.text,
              onChanged: (value) => setState(() => _values[key] = value),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final field in _fields) {
      if (_filter.isNotEmpty &&
          !'${field['group']} ${field['label']} ${field['key']}'
              .toLowerCase()
              .contains(_filter)) {
        continue;
      }
      groups.putIfAbsent('${field['group']}', () => []).add(field);
    }
    final dirty = _values.entries.any(
      (entry) => _initial[entry.key] != entry.value,
    );
    return AlertDialog(
      title: const Text('Preferences'),
      content: SizedBox(
        width: 720,
        height: MediaQuery.sizeOf(context).height * .62,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Find a preference',
              ),
              onChanged: (value) =>
                  setState(() => _filter = value.toLowerCase().trim()),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_saved)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.backend.ownsDaemon
                      ? 'Saved. Restart the player to apply startup preferences.'
                      : 'Saved. Restart the player instance you connected to for startup preferences to take effect.',
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                children: [
                  for (final group in groups.entries)
                    ExpansionTile(
                      key: ValueKey('${group.key}:$_filter'),
                      initiallyExpanded:
                          _filter.isNotEmpty || group.key == 'Playback',
                      title: Text(group.key),
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      children: group.value.map(_field).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _saved),
          child: const Text('Done'),
        ),
        if (_saved && widget.backend.ownsDaemon)
          OutlinedButton(
            onPressed: _busy || dirty ? null : _restart,
            child: const Text('Restart player'),
          ),
        FilledButton(
          onPressed: _busy || !dirty ? null : _save,
          child: const Text('Save changes'),
        ),
      ],
    );
  }
}
