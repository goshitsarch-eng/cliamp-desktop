import 'setup_save_audit.dart' as setup_save_audit;
import 'jobs_audit.dart' as jobs_audit;
import 'recovery_audit.dart' as recovery_audit;
import 'download_audit.dart' as download_audit;
import 'palette_audit.dart' as palette_audit;
import 'history_audit.dart' as history_audit;
// Native integration audit: real Flutter window and real Go sidecar, no mocks.
import 'dart:convert';
import 'dart:io';
import 'interaction_audit.dart' as interactions;
import 'library_audit.dart' as library_audit;
import 'keyboard_audit.dart' as keyboard_audit;
import 'source_audit.dart' as source_audit;
import 'lyrics_audit.dart' as lyrics_audit;
import 'input_audit.dart' as input_audit;
import 'podcast_audit.dart' as podcast_audit;
import 'provider_audit.dart' as provider_audit;
import 'package:cliamp_desktop/src/app.dart';
import 'package:cliamp_desktop/src/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final root =
    Platform.environment['CLIAMP_AUDIT_ROOT'] ?? '/tmp/cliamp-native-audit';
final results = <Map<String, dynamic>>[];
final errors = <String>[];
String current = 'bootstrap', window = '', profilePath = '';
late CliampBackend backend;
Future<void> tick(WidgetTester t, [int ms = 350]) async {
  await t.pump();
  await Future<void>.delayed(Duration(milliseconds: ms));
  await t.pump();
  await t.pump();
  for (final render in t.allRenderObjects) {
    if (render.toStringShort().contains('OVERFLOWING')) {
      final e = '$current: ${render.toStringShort()}';
      if (!errors.contains(e)) errors.add(e);
    }
  }
}

Future<void> waitFor(WidgetTester t, Finder f) async {
  for (var n = 0; n < 60; n++) {
    try {
      if (f.evaluate().isNotEmpty) return;
    } on StateError catch (error) {
      // A finder ending in .first can be empty while a real RPC refreshes.
      if (error.message != 'No element') rethrow;
    }
    await tick(t, 100);
  }
  throw StateError('Missing UI: $f');
}

bool disabled(Finder finder) {
  bool? interactive(Widget widget) => switch (widget) {
    ButtonStyleButton() =>
      widget.onPressed == null && widget.onLongPress == null,
    IconButton() => widget.onPressed == null,
    PopupMenuItem() => !widget.enabled,
    DropdownButton<String>() => widget.onChanged == null,
    DropdownButton<int>() => widget.onChanged == null,
    DropdownButton<double>() => widget.onChanged == null,
    CheckboxListTile() => widget.onChanged == null,
    SwitchListTile() => widget.onChanged == null,
    TextField() => widget.enabled == false,
    _ => null,
  };
  final element = finder.evaluate().first;
  var result = interactive(element.widget);
  element.visitAncestorElements((ancestor) {
    result ??= interactive(ancestor.widget);
    return result == null;
  });
  return result ?? false;
}

Future<void> click(
  WidgetTester t,
  Finder f,
  String label, {
  bool waitForIdle = true,
}) async {
  await waitFor(t, f);
  await t.ensureVisible(f.first);
  await waitFor(t, f.first.hitTestable());
  for (var n = 0; n < 100 && disabled(f.first); n++) {
    await tick(t, 100);
  }
  expect(
    disabled(f.first),
    isFalse,
    reason: '$label must be enabled before activation',
  );
  await t.tap(f.first);
  await tick(t);
  for (
    var n = 0;
    waitForIdle &&
        n < 100 &&
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    n++
  ) {
    await tick(t, 100);
  }
  results.add({'stage': current, 'action': 'click', 'control': label});
  if (results.length % 20 == 0) await save();
}

Future<void> key(
  WidgetTester t,
  LogicalKeyboardKey k, {
  bool ctrl = false,
}) async {
  if (ctrl || k == LogicalKeyboardKey.enter) {
    final nativeName = switch (k) {
      LogicalKeyboardKey.enter => 'Return',
      LogicalKeyboardKey.arrowLeft => 'Left',
      LogicalKeyboardKey.arrowRight => 'Right',
      LogicalKeyboardKey.arrowUp => 'Up',
      LogicalKeyboardKey.arrowDown => 'Down',
      _ => k.keyLabel.toLowerCase(),
    };
    final result = await Process.run('python3', [
      '$root/window.py',
      'key',
      window,
      if (ctrl) 'Control_L',
      nativeName,
    ]);
    expect(result.exitCode, 0);
    await tick(t);
    results.add({
      'stage': current,
      'action': 'native-key',
      'control': '${ctrl ? 'Ctrl+' : ''}$nativeName',
    });
    return;
  }
  await t.sendKeyEvent(k);
  await tick(t);
  results.add({
    'stage': current,
    'action': 'key',
    'control': '${ctrl ? 'Ctrl+' : ''}${k.keyLabel}',
  });
}

Future<void> resize(WidgetTester t, int w, int h) async {
  final r = await Process.run('python3', [
    '$root/window.py',
    'resize',
    window,
    '$w',
    '$h',
  ]);
  if (r.exitCode != 0) throw StateError('${r.stderr}');
  await tick(t);
  results.add({
    'stage': current,
    'action': 'native-resize',
    'width': t.view.physicalSize.width,
    'height': t.view.physicalSize.height,
  });
}

Future<void> capture(String name) async {
  await Directory('$root/evidence').create(recursive: true);
  final r = await Process.run('import', [
    '-window',
    window,
    '$root/evidence/$name.png',
  ]);
  if (r.exitCode != 0) throw StateError('${r.stderr}');
  final png = ByteData.sublistView(
    await File('$root/evidence/$name.png').readAsBytes(),
    16,
    24,
  );
  final size =
      WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
  expect(
    png.getUint32(0),
    size.width.toInt(),
    reason: 'Screenshot must match the tested native window',
  );
  expect(png.getUint32(4), size.height.toInt());
}

Future<void> save() => File(
  '$root/native-results.json',
).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
Future<void> stage(
  WidgetTester t,
  String name,
  Future<void> Function() run,
) async {
  current = name;
  final start = errors.length;
  try {
    await run();
    await tick(t);
    await capture(name);
    results.add({
      'stage': name,
      'time': DateTime.now().toUtc().toIso8601String(),
      'status': errors.length == start ? 'PASS' : 'FAIL',
      'frameworkErrors': errors.skip(start).toList(),
    });
  } catch (e, s) {
    results.add({
      'stage': name,
      'time': DateTime.now().toUtc().toIso8601String(),
      'status': 'FAIL',
      'error': '$e',
      'stack': '$s',
    });
    try {
      await capture('$name-failed');
    } catch (_) {}
    await save();
    throw StateError('Audit stage failed: $name. See native-results.json.');
  }
  await save();
  debugPrint('AUDIT ${results.last['status']}: $name');
  if (errors.length != start) {
    throw StateError('Framework errors in $name. See native-results.json.');
  }
}

const pages = [
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
Future<void> nav(WidgetTester t, String name) async {
  await resize(t, 1280, 940);
  final sidebar = find.byType(ListView).first;
  final scroll = find
      .descendant(of: sidebar, matching: find.byType(Scrollable))
      .first;
  await t.scrollUntilVisible(
    find.descendant(of: sidebar, matching: find.text(name)),
    200,
    scrollable: scroll,
    maxScrolls: 20,
  );
  await click(t, find.text(name).first, 'Navigate $name');
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      250,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 30,
    );
  }
  await t.ensureVisible(f.first);
}

Future<void> dialogSizes(WidgetTester t, String name) async {
  await resize(t, 640, 480);
  await capture('$name-640x480');
  await resize(t, 400, 300);
  await capture('$name-400x300');
  await resize(t, 1280, 940);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('real native desktop audit', (t) async {
    final binary = Platform.environment['CLIAMP_BINARY'];
    expect(binary, isNotNull);
    final profile =
        Platform.environment['CLIAMP_AUDIT_PROFILE'] ??
        '$root/native-profile-${DateTime.now().millisecondsSinceEpoch}';
    profilePath = profile;
    final env = <String, String>{
      ...Platform.environment,
      'HOME': '$profile/home',
      'XDG_CONFIG_HOME': '$profile/config',
      'XDG_DATA_HOME': '$profile/data',
      'XDG_STATE_HOME': '$profile/state',
      'XDG_CACHE_HOME': '$profile/cache',
      'XDG_RUNTIME_DIR': '$profile/run',
      'CLIAMP_CONFIG_DIR': '$profile/config/cliamp',
      'ALSA_CONFIG_PATH': '$root/profile/asound.conf',
    };
    for (final k in [
      'HOME',
      'XDG_CONFIG_HOME',
      'XDG_DATA_HOME',
      'XDG_STATE_HOME',
      'XDG_CACHE_HOME',
      'XDG_RUNTIME_DIR',
      'CLIAMP_CONFIG_DIR',
    ]) {
      await Directory(env[k]!).create(recursive: true);
    }
    final configFile = File('${env['CLIAMP_CONFIG_DIR']}/config.toml');
    if (!await configFile.exists()) {
      await configFile.writeAsString(
        'provider = "local"\nauto_play = false\nvolume = -24\n',
      );
    }
    await File('$root/profile-path.txt').writeAsString(profile);
    backend = CliampBackend(executable: binary, environment: env);
    final handler = FlutterError.onError;
    FlutterError.onError = (d) {
      final e = '$current: ${d.exceptionAsString()}';
      if (!errors.contains(e)) {
        errors.add(e);
        debugPrint('AUDIT FRAMEWORK ERROR: $e');
        debugPrintStack(stackTrace: d.stack, maxFrames: 40);
        results.add({
          'stage': current,
          'frameworkException': e,
          'stack': '${d.stack}',
        });
      }
    };
    try {
      await t.pumpWidget(CliampApp(backend: backend));
      await waitFor(t, find.text('Engine connected'));
      final info = await Process.run('xwininfo', ['-name', 'Cliamp']);
      window = RegExp(
        r'Window id: (0x[0-9a-f]+)',
      ).firstMatch('${info.stdout}')!.group(1)!;
      final owner = await Process.run('xprop', ['-id', window, '_NET_WM_PID']);
      expect(
        '${owner.stdout}'.trim().endsWith('= $pid'),
        isTrue,
        reason: 'The audit must interact with its own native process',
      );
      await Process.run('python3', [
        '$root/window.py',
        'move',
        window,
        '0',
        '0',
      ]);
      final phase = Platform.environment['CLIAMP_AUDIT_PHASE'];
      if (phase != 'reopen') {
        await stage(t, 'fresh-launch', () async {
          await waitFor(t, find.text('Your music belongs here'));
          expect(find.text('Your music belongs here'), findsOneWidget);
        });
      }
      if (phase == 'reopen') {
        await stage(t, 'reopen-persisted-library-and-preferences', () async {
          await nav(t, 'Settings');
          await click(
            t,
            find.text('All preferences'),
            'Open persisted preferences',
          );
          await interactions.enter(
            t,
            interactions.hint('Find a preference'),
            'volume_min',
          );
          expect(
            t
                .widget<TextField>(interactions.field('Volume min'))
                .controller!
                .text,
            '-48',
          );
          await click(t, find.text('Done'), 'Close preferences');
          await nav(t, 'Playlists');
          await waitFor(t, find.text('Audit Café 春'));
          await click(t, find.text('Audit Café 春'), 'Open persisted playlist');
          await waitFor(t, find.byTooltip('Track actions'));
          expect(find.byTooltip('Track actions'), findsNWidgets(2));
          await nav(t, 'History');
          await waitFor(t, find.byTooltip('Track actions'));
        });
      } else if (phase == 'preferences') {
        await interactions.preferences(t);
      } else if (phase == 'setup-save') {
        await setup_save_audit.exercise(t);
      } else if (phase == 'jobs') {
        await jobs_audit.exercise(t);
      } else if (phase == 'recovery') {
        await recovery_audit.exercise(t);
      } else if (phase == 'download') {
        await download_audit.exercise(t);
      } else if (phase == 'palette') {
        await palette_audit.exercise(t);
      } else if (phase == 'history') {
        await history_audit.exercise(t);
      } else if (phase == 'podcasts') {
        await podcast_audit.exercise(t);
      } else if (phase == 'input-errors') {
        await input_audit.exercise(t);
      } else if (phase == 'visualizer') {
        await library_audit.visualizer(t);
      } else if (phase == 'lyrics') {
        await lyrics_audit.exercise(t);
      } else if (phase == 'location-allow') {
        await provider_audit.locationConsent(t);
      } else if (phase == 'providers') {
        await provider_audit.exercise(t);
      } else if (phase == 'playback') {
        await nav(t, 'Queue');
        await interactions.loadSources(
          t,
          '$root/profile/home/Music/Aurora - Blue Hour.wav',
        );
        await interactions.playback(t);
      } else if ([
        'library',
        'batches',
        'plugins',
        'keyboard',
        'sources',
        'files',
      ].contains(phase)) {
        await nav(t, 'Queue');
        await interactions.loadSources(
          t,
          '$root/profile/home/Music/Aurora - Blue Hour.wav\n$root/profile/home/Music/Björk Test - Café 春.wav',
        );
        if (phase == 'library') await library_audit.exercise(t);
        if (phase == 'batches') await library_audit.batches(t);
        if (phase == 'plugins') await library_audit.plugins(t);
        if (phase == 'keyboard') await keyboard_audit.exercise(t);
        if (phase == 'sources') await source_audit.exercise(t);
        if (phase == 'files') await library_audit.fileDialogs(t);
      } else if (phase == 'setup') {
        await interactions.setup(t);
      } else {
        if (Platform.environment['CLIAMP_AUDIT_INTERACTIONS_ONLY'] != '1') {
          for (final page in pages) {
            await nav(t, page);
            for (final size in [
              const Size(1280, 940),
              const Size(900, 650),
              const Size(640, 480),
              const Size(400, 300),
              const Size(1600, 500),
              const Size(640, 1400),
            ]) {
              await stage(
                t,
                'layout-${page.replaceAll(' ', '-')}-${size.width.toInt()}x${size.height.toInt()}',
                () async {
                  await resize(t, size.width.toInt(), size.height.toInt());
                },
              );
            }
          }
        }
        await nav(t, 'Queue');
        await stage(t, 'add-music-dialog', () async {
          await key(t, LogicalKeyboardKey.keyO, ctrl: true);
          expect(find.text('Add your music'), findsOneWidget);
          await dialogSizes(t, 'add-music');
          await click(t, find.text('Cancel'), 'Cancel add music');
        });
        await stage(t, 'command-palette-dialog', () async {
          await key(t, LogicalKeyboardKey.keyK, ctrl: true);
          expect(find.text('Commands & keyboard shortcuts'), findsOneWidget);
          await dialogSizes(t, 'palette');
          await key(t, LogicalKeyboardKey.escape);
        });
        await nav(t, 'Settings');
        await stage(t, 'preferences-dialog', () async {
          await click(t, find.text('All preferences'), 'All preferences');
          await waitFor(t, find.text('Playback'));
          await dialogSizes(t, 'preferences');
          await click(t, find.text('Done'), 'Done preferences');
        });
        await stage(t, 'setup-dialog', () async {
          await reveal(t, find.text('Connect service'));
          await click(t, find.text('Connect service'), 'Connect service');
          await waitFor(t, find.text('Connect your music'));
          await dialogSizes(t, 'setup');
          await click(t, find.text('Cancel'), 'Cancel setup');
        });
        await nav(t, 'Plugins');
        await stage(t, 'plugin-manager-dialog', () async {
          await click(t, find.text('Manage plugins'), 'Manage plugins');
          await waitFor(t, find.text('Review source'));
          await dialogSizes(t, 'plugins');
          await click(t, find.text('Done'), 'Done plugins');
        });
        await input_audit.exercise(t);
        await interactions.exercise(t);
        await library_audit.exercise(t);
        await library_audit.fileDialogs(t);
        await keyboard_audit.exercise(t);
        await source_audit.exercise(t);
        await lyrics_audit.exercise(t);
        await provider_audit.exercise(t);
        await podcast_audit.exercise(t);
        await history_audit.exercise(t);
        await palette_audit.exercise(t);
        await download_audit.exercise(t);
        await recovery_audit.exercise(t);
        await jobs_audit.exercise(t);
        await setup_save_audit.exercise(t);
      }
    } finally {
      await t.pumpWidget(const SizedBox());
      await backend.close();
      FlutterError.onError = handler;
      await save();
    }
    expect(
      errors,
      isEmpty,
      reason:
          'Framework errors anywhere in the native run must fail the audit.',
    );
    expect(
      results.where((r) => r['status'] == 'FAIL').toList(),
      isEmpty,
      reason: 'See $root/native-results.json and screenshots.',
    );
  }, timeout: const Timeout(Duration(minutes: 90)));
}
