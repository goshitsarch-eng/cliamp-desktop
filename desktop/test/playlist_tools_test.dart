import 'package:cliamp_desktop/src/backend.dart';
import 'package:cliamp_desktop/src/playlist_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _PlaylistBackend implements PlayerBackend {
  final calls = <({String operation, Map<String, dynamic> params})>[];
  bool recursive = true;

  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add((operation: operation, params: Map.of(params)));
    switch (operation) {
      case 'playlist.capabilities':
        return {
          'replace': true,
          'directories': true,
          'undo': true,
          'import': true,
          'can_add': true,
        };
      case 'provider.tracks':
        final offset = params['offset'] as int? ?? 0;
        return {
          'total': 1200,
          'tracks': List.generate(
            200,
            (index) => {
              'path': '/track-${offset + index}.mp3',
              'title': 'Track ${offset + index}',
              'provider_meta': {'identity': 'kept'},
            },
          ),
        };
      case 'playlist.dirs.list':
        return {
          'directories': [
            {'path': '/music', 'recursive': recursive},
          ],
        };
      case 'playlist.dirs.recursive':
        recursive = params['name'] == 'on';
        return {'ok': true};
      default:
        return {'ok': true};
    }
  }

  @override
  Future<void> connect() async {}
  @override
  Future<void> close() async {}
  @override
  Future<Map<String, dynamic>> snapshot() async => {};
  @override
  Future<Map<String, dynamic>> capabilities() async => {};
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Stream<List<double>> get spectrum => const Stream.empty();
}

void main() {
  Future<void> showTools(WidgetTester tester, _PlaylistBackend backend) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistToolsDialog(
            backend: backend,
            provider: 'local',
            playlist: 'Mix',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('large saved playlists sort on the backend and page safely', (
    tester,
  ) async {
    final backend = _PlaylistBackend();
    await showTools(tester, backend);
    expect(find.text('1200 tracks'), findsOneWidget);
    await tester.tap(find.text('Sort and save'));
    await tester.pumpAndSettle();
    final sort = backend.calls.firstWhere(
      (call) => call.operation == 'playlist.sort',
    );
    expect(sort.params, {
      'provider': 'local',
      'playlist': 'Mix',
      'sort': 'title',
    });
    expect(
      backend.calls.where((call) => call.operation == 'playlist.replace'),
      isEmpty,
    );
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(
      backend.calls
          .lastWhere((call) => call.operation == 'provider.tracks')
          .params['offset'],
      200,
    );
    await tester.tap(find.byTooltip('Move track down').first);
    await tester.pumpAndSettle();
    final move = backend.calls.firstWhere(
      (call) => call.operation == 'playlist.move',
    );
    expect(move.params['index'], 200);
    expect(move.params['to'], 201);
    expect((move.params['track'] as Map)['provider_meta'], {
      'identity': 'kept',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory recursion and undo use saved-playlist operations', (
    tester,
  ) async {
    final backend = _PlaylistBackend();
    await showTools(tester, backend);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final recursive = backend.calls.firstWhere(
      (call) => call.operation == 'playlist.dirs.recursive',
    );
    expect(recursive.params, {
      'provider': 'local',
      'playlist': 'Mix',
      'path': '/music',
      'name': 'off',
    });
    await tester.tap(find.text('Undo last playlist edit'));
    await tester.pumpAndSettle();
    expect(
      backend.calls.where((call) => call.operation == 'playlist.undo'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native file selection imports directly into the saved playlist',
    (tester) async {
      final backend = _PlaylistBackend();
      var selected = ['/music/First song.flac', '/music/Collection.m3u8'];
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'openFile');
        expect((call.arguments as Map)['multiple'], true);
        expect((call.arguments as Map)['confirmButtonText'], 'Add to playlist');
        return selected;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await showTools(tester, backend);
      await tester.tap(find.text('Add files'));
      await tester.pumpAndSettle();
      final imports = backend.calls.where(
        (call) => call.operation == 'playlist.import',
      );
      expect(imports, hasLength(1));
      expect(imports.single.params, {
        'provider': 'local',
        'playlist': 'Mix',
        'args': selected,
      });
      expect(
        backend.calls.where(
          (call) =>
              call.operation.startsWith('tracks.') ||
              call.operation == 'sources.load',
        ),
        isEmpty,
      );
      selected = [];
      await tester.tap(find.text('Add files'));
      await tester.pumpAndSettle();
      expect(imports, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
