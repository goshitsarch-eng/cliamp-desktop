import 'dart:async';

import 'package:cliamp_desktop/src/backend.dart';
import 'package:cliamp_desktop/src/visualizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Json = Map<String, dynamic>;

class _VisualizerBackend implements PlayerBackend, VisualizerFrameBackend {
  final calls = <({String operation, _Json params})>[];
  String theme = 'Default';
  int mode = 0;
  int frames = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  final playback = <String, dynamic>{
    'state': 'playing',
    'volume': -12.0,
    'position': 20.0,
    'seekable': true,
    'track': {
      'title': 'Private episode title',
      'artist': 'Podcast artist',
      'album': 'Season one',
    },
  };
  Completer<void>? pendingPreview;
  Completer<void>? pendingFrame;
  @override
  Future<void> connect() async {}
  @override
  Future<_Json> snapshot() async => Map.of(playback);
  @override
  Future<_Json> capabilities() async => {};
  @override
  Stream<_Json> get events => const Stream.empty();
  @override
  Stream<List<double>> get spectrum => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<_Json> call(String operation, [_Json params = const {}]) async {
    calls.add((operation: operation, params: Map.of(params)));
    if (operation == 'toggle') {
      playback['state'] = playback['state'] == 'playing' ? 'paused' : 'playing';
    }
    if (operation == 'volume.adjust') {
      playback['volume'] =
          (playback['volume'] as num) + (params['value'] as num);
    }
    if (operation == 'seek') {
      playback['position'] =
          (playback['position'] as num) + (params['value'] as num);
    }
    if (operation == 'desktop.vis' && params['name'] == 'list') {
      return {
        'items': ['Bars', 'Waves'],
        'index': mode,
      };
    }
    if (operation == 'desktop.theme' && params['name'] == 'list') {
      return {
        'items': ['Default', 'Ocean'],
      };
    }
    if (operation.startsWith('desktop.theme')) {
      if (params['name'] == 'Ocean' &&
          operation.endsWith('.preview') &&
          pendingPreview != null) {
        await pendingPreview!.future;
      }
      theme = params['name'] as String;
    }
    if (operation.startsWith('desktop.vis')) mode = params['index'] as int;
    return {'ok': true, 'index': mode};
  }

  @override
  Future<_Json> readFrame(int width, int height) async {
    frames++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (pendingFrame != null) await pendingFrame!.future;
      return {
        'frame': '\u001b[38;2;129;230;205m▂▅▇▃\u001b[0m',
        'index': mode,
        'visualizer': ['Bars', 'Waves'][mode],
        'theme': {'name': theme, 'bg': '#101217', 'fg': '#ddeeff'},
      };
    } finally {
      inFlight--;
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  _VisualizerBackend backend, {
  void Function(Future<void> Function())? cleanup,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: EngineVisualizer(
          backend: backend,
          playbackState: Map.of(backend.playback),
          operations: const [
            {'name': 'desktop.vis.frame'},
            {'name': 'desktop.theme.preview'},
            {'name': 'desktop.vis.preview'},
            {'name': 'toggle'},
            {'name': 'prev'},
            {'name': 'next'},
            {'name': 'volume.adjust'},
            {'name': 'seek'},
          ],
          onError: (error) => fail(error),
          onCleanupReady: cleanup,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _chooseOcean(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.text('Ocean').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets(
    'fullscreen transports playback and keeps track details optional',
    (tester) async {
      final backend = _VisualizerBackend();
      await _mount(tester, backend);
      await tester.tap(find.byTooltip('Enter fullscreen visualizer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Private episode title'), findsOneWidget);
      expect(find.text('Podcast artist · Season one'), findsOneWidget);
      expect(find.text('-12 dB'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(backend.playback['state'], 'paused');
      expect(find.text('Play'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous track (,)'));
      await tester.pump();
      await tester.tap(find.byTooltip('Next track (.)'));
      await tester.pump();
      await tester.tap(find.byTooltip('Seek forward 5 seconds (Right)'));
      await tester.pump();
      expect(backend.playback['position'], 25);
      await tester.tap(find.byTooltip('Raise volume (+)'));
      await tester.pump();
      expect(find.text('-11 dB'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide track information (T)'));
      await tester.pump();
      expect(find.text('Private episode title'), findsNothing);
      expect(find.text('Podcast artist · Season one'), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      expect(
        backend.calls.where((call) => call.operation == 'prev'),
        hasLength(1),
      );
      expect(
        backend.calls.where((call) => call.operation == 'next'),
        hasLength(1),
      );
      expect(backend.maxInFlight, 1);
      await tester.tap(find.byTooltip('Exit fullscreen visualizer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fullscreen keyboard controls are scoped and live streams cannot seek',
    (tester) async {
      final backend = _VisualizerBackend();
      backend.playback['seekable'] = false;
      await _mount(tester, backend);
      tester.view.physicalSize = const Size(900, 650);
      await tester.tap(find.byTooltip('Enter fullscreen visualizer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.comma,
        LogicalKeyboardKey.period,
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.equal,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(
        backend.calls.where((call) => call.operation == 'toggle'),
        hasLength(1),
      );
      expect(
        backend.calls.where((call) => call.operation == 'prev'),
        hasLength(1),
      );
      expect(
        backend.calls.where((call) => call.operation == 'next'),
        hasLength(1),
      );
      expect(
        backend.calls
            .where((call) => call.operation == 'volume.adjust')
            .map((call) => call.params['value']),
        [-1, 1],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(backend.calls.where((call) => call.operation == 'seek'), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(find.text('Private episode title'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(find.text('Private episode title'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(backend.mode, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byTooltip('Exit fullscreen visualizer'), findsNothing);
      final toggles = backend.calls
          .where((call) => call.operation == 'toggle')
          .length;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        backend.calls.where((call) => call.operation == 'toggle'),
        hasLength(toggles),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance preview cancels without writing persistent appearance',
    (tester) async {
      final backend = _VisualizerBackend();
      await _mount(tester, backend);
      await _chooseOcean(tester);
      expect(backend.theme, 'Ocean');
      expect(
        backend.calls.where(
          (call) =>
              call.operation == 'desktop.theme' &&
              call.params['name'] != 'list',
        ),
        isEmpty,
      );
      await tester.tap(find.text('Cancel preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.theme, 'Default');
      expect(
        backend.calls.where(
          (call) =>
              call.operation == 'desktop.theme' &&
              call.params['name'] != 'list',
        ),
        isEmpty,
      );
      expect(find.text('Apply appearance'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'apply persists chosen appearance and fullscreen shares the direct frame reader',
    (tester) async {
      final backend = _VisualizerBackend();
      await _mount(tester, backend);
      await _chooseOcean(tester);
      await tester.tap(find.text('Apply appearance'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        backend.calls.where(
          (call) =>
              call.operation == 'desktop.theme' &&
              call.params['name'] == 'Ocean',
        ),
        hasLength(1),
      );
      await tester.tap(find.byTooltip('Enter fullscreen visualizer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byTooltip('Exit fullscreen visualizer'), findsOneWidget);
      backend.pendingFrame = Completer<void>();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(backend.maxInFlight, 1);
      expect(
        backend.calls.where((call) => call.operation == 'desktop.vis.frame'),
        isEmpty,
      );
      backend.pendingFrame!.complete();
      backend.pendingFrame = null;
      await tester.pump();
      await tester.tap(find.byTooltip('Exit fullscreen visualizer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('window cleanup waits for a pending preview before restoring', (
    tester,
  ) async {
    final backend = _VisualizerBackend()..pendingPreview = Completer<void>();
    Future<void> Function()? cleanup;
    await _mount(tester, backend, cleanup: (callback) => cleanup = callback);
    await _chooseOcean(tester);
    final restored = cleanup!();
    expect(backend.theme, 'Default');
    backend.pendingPreview!.complete();
    await tester.pump();
    await restored;
    expect(backend.theme, 'Default');
    final changes = backend.calls
        .where((call) => call.operation == 'desktop.theme.preview')
        .toList();
    expect(changes.map((call) => call.params['name']), ['Ocean', 'Default']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test(
    'ANSI parser preserves RGB colors and strips non-styling terminal controls',
    () {
      final spans = ansiSpans('\u001b[2J\u001b[38;2;10;20;30mA\u001b[0m B');
      expect(spans.map((span) => span.text).join(), 'A B');
      expect(spans.first.style?.color, const Color.fromARGB(255, 10, 20, 30));
      expect(spans.last.style?.color, isNull);
    },
  );
}
