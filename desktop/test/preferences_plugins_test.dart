import 'package:cliamp_desktop/src/backend.dart';
import 'package:cliamp_desktop/src/plugin_manager.dart';
import 'package:cliamp_desktop/src/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ManagementBackend implements DesktopManagementBackend {
  final preferenceChanges = <Map<String, String>>[];
  final pluginCalls = <({String action, Map<String, dynamic> values})>[];
  int restarts = 0;
  final extraFields = <Map<String, dynamic>>[];

  @override
  bool get ownsDaemon => true;
  @override
  Future<void> restartOwnedEngine() async => restarts++;
  @override
  Future<Map<String, dynamic>> preferencesSchema() async => {
    'ok': true,
    'fields': [
      ...extraFields,
      {
        'key': 'volume',
        'label': 'Volume',
        'group': 'Playback',
        'type': 'number',
        'value': '-10',
        'min': -90,
        'max': 6,
      },
      {
        'key': 'mono',
        'label': 'Mono',
        'group': 'Playback',
        'type': 'bool',
        'value': 'false',
      },
      {
        'key': 'audio_device',
        'label': 'Audio device',
        'group': 'Audio',
        'type': 'string',
        'value': '',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> savePreferences(
    Map<String, String> values,
  ) async {
    preferenceChanges.add(Map.of(values));
    return {'ok': true, 'restart_required': values.isNotEmpty};
  }

  @override
  Future<Map<String, dynamic>> pluginAction(
    String action, [
    Map<String, dynamic> values = const {},
  ]) async {
    pluginCalls.add((action: action, values: Map.of(values)));
    if (action == 'list') return {'ok': true, 'plugins': []};
    if (action == 'prepare') {
      return {
        'ok': true,
        'review': {
          'token': 'review-token',
          'action': 'install',
          'name': 'Example',
          'source': 'owner/cliamp-plugin-example',
          'sha256': 'reviewed-sha256',
          'permissions': ['control'],
          'implicit_access': 'Public HTTP and file reads',
          'code': 'plugin.register({type="hook"})',
        },
      };
    }
    return {'ok': true, 'restart_required': true};
  }
}

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preferences explain invalid values before submitting', (
    tester,
  ) async {
    final backend = _ManagementBackend();
    backend.extraFields.addAll([
      {
        'key': 'buffer',
        'label': 'Buffer',
        'group': 'Audio',
        'type': 'integer',
        'value': '100',
        'min': 50,
        'max': 5000,
      },
      {
        'key': 'eq',
        'label': 'EQ',
        'group': 'Audio',
        'type': 'equalizer',
        'value': '[0,0,0,0,0,0,0,0,0,0]',
      },
      {
        'key': 'names',
        'label': 'Names',
        'group': 'Audio',
        'type': 'list',
        'value': '[]',
      },
    ]);
    await _open(tester, PreferencesDialog(backend: backend));
    for (final item in [
      ('Volume', '999', '-10', 'outside the supported range'),
      ('Volume', 'NaN', '-10', 'finite number'),
      ('Buffer', '3.5', '100', 'whole number'),
      ('EQ', '[13,0,0,0,0,0,0,0,0,0]', '[0,0,0,0,0,0,0,0,0,0]', 'ten gains'),
      ('Names', '[1]', '[]', 'single-line names'),
      ('Names', 'not JSON', '[]', 'single-line names'),
    ]) {
      await tester.enterText(find.byType(TextField).first, item.$1);
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == item.$1,
      );
      await tester.enterText(input, item.$2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('${item.$1}:'), findsOneWidget);
      expect(find.textContaining(item.$4), findsOneWidget);
      expect(backend.preferenceChanges, isEmpty);
      await tester.enterText(input, item.$3);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('preferences save only edits and offer an owned engine restart', (
    tester,
  ) async {
    final backend = _ManagementBackend();
    await _open(tester, PreferencesDialog(backend: backend));
    await tester.enterText(find.widgetWithText(TextField, 'Volume'), '-6');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(backend.preferenceChanges, [
      {'volume': '-6'},
    ]);
    expect(find.text('Restart player'), findsOneWidget);
    await tester.tap(find.text('Restart player'));
    await tester.pumpAndSettle();
    expect(backend.restarts, 1);
    expect(find.byType(PreferencesDialog), findsNothing);
  });

  testWidgets('preferences search exposes matching grouped fields', (
    tester,
  ) async {
    final backend = _ManagementBackend();
    await _open(tester, PreferencesDialog(backend: backend));
    await tester.enterText(find.byType(TextField).first, 'audio device');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Audio device'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Volume'), findsNothing);
  });

  testWidgets('plugin installation waits for explicit exact-content approval', (
    tester,
  ) async {
    final backend = _ManagementBackend();
    await _open(tester, PluginManagerDialog(backend: backend));
    await tester.enterText(
      find.byType(TextField),
      'owner/cliamp-plugin-example',
    );
    await tester.tap(find.text('Review source'));
    await tester.pumpAndSettle();
    expect(
      backend.pluginCalls.where((call) => call.action == 'apply'),
      isEmpty,
    );
    expect(find.textContaining('reviewed-sha256'), findsOneWidget);
    expect(find.text('plugin.register({type="hook"})'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Trust and install');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    final apply = backend.pluginCalls.singleWhere(
      (call) => call.action == 'apply',
    );
    expect(apply.values, {
      'token': 'review-token',
      'source': 'owner/cliamp-plugin-example',
      'sha256': 'reviewed-sha256',
      'permissions': ['control'],
    });
    expect(backend.restarts, 0);
    expect(find.text('Restart player'), findsOneWidget);
  });

  testWidgets('cancelling a plugin review leaves the plugin unapproved', (
    tester,
  ) async {
    final backend = _ManagementBackend();
    await _open(tester, PluginManagerDialog(backend: backend));
    await tester.enterText(
      find.byType(TextField),
      'owner/cliamp-plugin-example',
    );
    await tester.tap(find.text('Review source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      backend.pluginCalls.where(
        (call) => call.action == 'apply' || call.action == 'trust',
      ),
      isEmpty,
    );
    expect(find.text('Restart player'), findsNothing);
  });
}
