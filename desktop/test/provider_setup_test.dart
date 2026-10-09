import 'package:cliamp_desktop/src/backend.dart';
import 'package:cliamp_desktop/src/provider_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Values = Map<String, String>;
typedef _Save = ({String provider, _Values values, bool verify});

class _SetupBackend implements ProviderSetupBackend {
  _SetupBackend({this.ownsDaemon = false});
  @override
  final bool ownsDaemon;
  final saves = <_Save>[];
  final schemas = <({String provider, _Values values})>[];
  int restarts = 0;
  bool rejectVerifiedSave = false;

  @override
  Future<Map<String, dynamic>> setupSchema(
    String provider, [
    _Values values = const {},
  ]) async {
    schemas.add((provider: provider, values: Map.of(values)));
    if (provider.isEmpty) {
      return {
        'providers': [
          {'key': 'example', 'name': 'Example Music'},
        ],
      };
    }
    final method = values['method'] ?? 'password';
    return {
      'provider': provider,
      'name': 'Example Music',
      'values': {'method': method, 'username': '', 'password': ''},
      'picker': {
        'key': 'method',
        'label': 'Connection type',
        'options': [
          {'value': 'password', 'label': 'Password login'},
          {'value': 'api_key', 'label': 'API key login'},
        ],
      },
      'fields': [
        {'key': 'username', 'label': 'Account name', 'required': true},
        if (method == 'password')
          {
            'key': 'password',
            'label': 'Account password',
            'required': true,
            'secret': true,
          }
        else
          {
            'key': 'token',
            'label': 'API key',
            'required': true,
            'secret': true,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> saveProvider(
    String provider,
    _Values values, {
    bool verifyConnection = true,
  }) async {
    saves.add((
      provider: provider,
      values: Map.of(values),
      verify: verifyConnection,
    ));
    return {'ok': !(rejectVerifiedSave && verifyConnection)};
  }

  @override
  Future<void> restartOwnedEngine() async => restarts++;
}

Future<void> _openSetup(
  WidgetTester tester,
  _SetupBackend backend, {
  ValueChanged<bool?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 950);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (_) => ProviderSetupDialog(backend: backend),
              );
              onResult?.call(result);
            },
            child: const Text('Configure'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Configure'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Example Music').last);
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.byKey(ValueKey('example:$key'));

Future<void> _credentials(WidgetTester tester) async {
  await tester.enterText(_field('username'), 'listener');
  await tester.enterText(_field('password'), 'fixture-password-not-a-secret');
}

Future<void> _chooseMethod(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('example:method')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'conditional fields retain entered credentials and mask secrets',
    (tester) async {
      final backend = _SetupBackend();
      await _openSetup(tester, backend);
      await tester.tap(find.text('Save provider'));
      await tester.pumpAndSettle();
      expect(backend.saves, isEmpty);
      expect(find.text('This field is required.'), findsNWidgets(2));

      await _credentials(tester);
      await _chooseMethod(tester, 'API key login');
      expect(_field('password'), findsNothing);
      expect(_field('token'), findsOneWidget);
      expect(backend.schemas.last.values['username'], 'listener');
      expect(
        backend.schemas.last.values['password'],
        'fixture-password-not-a-secret',
      );
      await _chooseMethod(tester, 'Password login');
      final password = tester.widget<TextFormField>(_field('password'));
      expect(password.controller!.text, 'fixture-password-not-a-secret');
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: _field('password'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.obscureText, isTrue);
      expect(editable.enableSuggestions, isFalse);

      await tester.tap(find.text('Save provider'));
      await tester.pumpAndSettle();
      expect(backend.saves, hasLength(1));
      expect(backend.saves.single.provider, 'example');
      expect(backend.saves.single.values['method'], 'password');
      expect(backend.saves.single.values['username'], 'listener');
      expect(
        backend.saves.single.values['password'],
        'fixture-password-not-a-secret',
      );
      expect(backend.saves.single.verify, isTrue);
      expect(find.text('Your provider is configured'), findsOneWidget);
      expect(backend.restarts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unsuccessful save requires explicit choice to skip verification',
    (tester) async {
      final backend = _SetupBackend()..rejectVerifiedSave = true;
      bool? dialogResult;
      await _openSetup(
        tester,
        backend,
        onResult: (result) => dialogResult = result,
      );
      await _credentials(tester);
      await tester.tap(find.text('Save provider'));
      await tester.pumpAndSettle();
      expect(find.text('Your provider is configured'), findsNothing);
      expect(
        find.textContaining('Unable to save this provider'),
        findsOneWidget,
      );
      expect(backend.saves.single.verify, isTrue);
      expect(find.text('Save without connection check'), findsOneWidget);
      expect(backend.saves, hasLength(1));

      await tester.tap(find.text('Save without connection check'));
      await tester.pumpAndSettle();
      expect(backend.saves.map((save) => save.verify), [true, false]);
      expect(find.text('Your provider is configured'), findsOneWidget);
      expect(find.text('Restart player'), findsNothing);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(dialogResult, isFalse);
      expect(backend.restarts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an owned engine restarts only when the listener chooses restart',
    (tester) async {
      final backend = _SetupBackend(ownsDaemon: true);
      bool? dialogResult;
      await _openSetup(
        tester,
        backend,
        onResult: (result) => dialogResult = result,
      );
      await _credentials(tester);
      await tester.tap(find.text('Save provider'));
      await tester.pumpAndSettle();
      expect(backend.restarts, 0);
      expect(find.text('Restart player'), findsOneWidget);
      expect(
        find.textContaining('This stops current playback'),
        findsOneWidget,
      );
      await tester.tap(find.text('Restart player'));
      await tester.pumpAndSettle();
      expect(backend.restarts, 1);
      expect(dialogResult, isTrue);
      expect(find.byType(ProviderSetupDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
