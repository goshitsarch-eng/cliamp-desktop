// Runs the desktop adapter against the real Go player, without Flutter or
// package:test. Build cliamp first, then run:
// CLIAMP_BINARY=/absolute/path/to/cliamp dart run tool/backend_smoke.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cliamp_desktop/src/backend.dart';

Future<void> main() async {
  try {
    await _smokeTest();
    stdout.writeln('PASS: desktop adapter and real cliamp lifecycle.');
  } catch (error, stack) {
    stderr.writeln('FAIL: $error');
    stderr.writeln(stack);
    exitCode = 1;
  }
}

Future<void> _smokeTest() async {
  final binary = Platform.environment['CLIAMP_BINARY'];
  _expect(
    binary != null && binary.isNotEmpty,
    'Set CLIAMP_BINARY to the Go player executable before running this test.',
  );
  final root = await Directory.systemTemp.createTemp('cliamp-desktop-');
  final children = <_TrackedProcess>[];
  final backends = <CliampBackend>[];
  final subscriptions = <StreamSubscription<dynamic>>[];

  Future<BackendProcess> launch(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    final process = _TrackedProcess(
      await Process.start(
        executable,
        arguments,
        environment: environment,
        runInShell: false,
      ),
      arguments,
    );
    children.add(process);
    return process;
  }

  try {
    final environment = <String, String>{
      ...Platform.environment,
      'HOME': '${root.path}/home',
      'USERPROFILE': '${root.path}/home',
      'APPDATA': '${root.path}/appdata',
      'LOCALAPPDATA': '${root.path}/localappdata',
      'XDG_CONFIG_HOME': '${root.path}/config',
      'XDG_DATA_HOME': '${root.path}/data',
      'XDG_CACHE_HOME': '${root.path}/cache',
      'XDG_STATE_HOME': '${root.path}/state',
      'XDG_RUNTIME_DIR': '${root.path}/run',
      'CLIAMP_CONFIG_DIR': '${root.path}/config/cliamp',
      if (Platform.isLinux) 'ALSA_CONFIG_PATH': '${root.path}/asound.conf',
    };
    for (final key in [
      'HOME',
      'APPDATA',
      'LOCALAPPDATA',
      'XDG_CONFIG_HOME',
      'XDG_DATA_HOME',
      'XDG_CACHE_HOME',
      'XDG_STATE_HOME',
      'XDG_RUNTIME_DIR',
      'CLIAMP_CONFIG_DIR',
    ]) {
      await Directory(environment[key]!).create(recursive: true);
    }
    await File(
      '${root.path}/asound.conf',
    ).writeAsString('pcm.!default { type null }\n');
    // A documented offline startup provider prevents a radio catalog fetch.
    await File('${environment['CLIAMP_CONFIG_DIR']}/config.toml').writeAsString(
      'provider = "podcast"\nauto_play = false\nrepeat = "one"\nvolume = -18\nvolume_min = -65\n',
    );
    final wav = File('${root.path}/Desktop smoke track.wav');
    await wav.writeAsBytes(_wave());

    final owner = CliampBackend(
      executable: binary,
      environment: environment,
      processLauncher: launch,
    );
    backends.add(owner);
    final events = <Map<String, dynamic>>[];
    final frames = <List<double>>[];
    final streamErrors = <Object>[];
    subscriptions.add(
      owner.events.listen(
        events.add,
        onError: (Object error) => streamErrors.add(error),
      ),
    );
    subscriptions.add(
      owner.spectrum.listen(
        frames.add,
        onError: (Object error) => streamErrors.add(error),
      ),
    );
    await owner.connect();
    _expect(
      children.where((child) => child.isDaemon).length == 1,
      'Connecting in an empty config must launch exactly one daemon.',
    );
    var daemon = children.singleWhere((child) => child.isDaemon);
    final initial = await owner.snapshot();
    final volumeFloor = initial['volume_min'];
    _expect(
      volumeFloor is num && volumeFloor == -65,
      'The runtime snapshot must report the configured volume floor.',
    );
    _expect(
      (initial['total'] ?? 0) == 0,
      'The isolated player must start with an empty queue.',
    );

    final capabilities = await owner.capabilities();
    final operations = (capabilities['operations'] as List)
        .map((operation) => (operation as Map)['name'])
        .toSet();
    for (final name in [
      'play',
      'pause',
      'seek.absolute',
      'volume',
      'eq',
      'queue',
      'queue.remove',
      'provider.list',
      'playlist.create',
      'plugin.commands',
    ]) {
      _expect(operations.contains(name), 'Missing capability: $name.');
    }
    stdout.writeln('PASS: owned daemon startup and capability discovery.');

    await owner.call('queue', {'path': wav.path});
    final first = await owner.snapshot();
    _expect(first['total'] == 1, 'Queue append did not add the WAV.');
    final staleRevision = first['playlist_revision'];
    _expect(
      staleRevision is int && staleRevision > 0,
      'A populated queue must have a nonzero playlist revision.',
    );
    await owner.call('queue', {'path': wav.path});
    final beforeConflict = await owner.snapshot();
    _expect(
      beforeConflict['playlist_revision'] != staleRevision,
      'Appending a second track must advance the playlist revision.',
    );
    var rejectedConflict = false;
    try {
      await owner.call('queue.remove', {
        'index': 0,
        'if_revision': staleRevision,
      });
    } on BackendException catch (error) {
      _expect(
        error.code == 'conflict',
        'Expected stable conflict error code, received ${error.code}.',
      );
      rejectedConflict = true;
    }
    _expect(rejectedConflict, 'A stale queue mutation must fail.');
    final afterConflict = await owner.snapshot();
    _expect(afterConflict['total'] == 2, 'A rejected edit changed the queue.');
    _expect(
      afterConflict['playlist_revision'] == beforeConflict['playlist_revision'],
      'A rejected edit changed the playlist revision.',
    );
    final queued = await owner.call('queue.list');
    final tracks = queued['tracks'] as List;
    _expect(
      tracks.length == 2 && tracks.every((track) => track['path'] == wav.path),
      'Queue listing lost or altered a path containing spaces.',
    );
    await owner.call('queue.remove', {
      'index': 1,
      'if_revision': afterConflict['playlist_revision'],
    });
    _expect(
      (await owner.snapshot())['total'] == 1,
      'A fresh queue edit did not remove the duplicate.',
    );
    stdout.writeln(
      'PASS: queue edits, paths with spaces, and revision conflicts.',
    );

    await owner.call('play');
    final playing = await _waitForSnapshot(
      owner,
      'local WAV playback',
      (state) => state['state'] == 'playing' && state['seekable'] == true,
    );
    _expect(
      (playing['track'] as Map)['path'] == wav.path,
      'The player loaded a different track.',
    );
    _expect(
      (playing['duration'] as num) > 10,
      'The WAV duration was not decoded.',
    );
    await owner.call('pause');
    await _waitForSnapshot(
      owner,
      'pause',
      (state) => state['state'] == 'paused',
    );
    await owner.call('seek.absolute', {'value': 3});
    await _waitForSnapshot(
      owner,
      'absolute seek while paused',
      (state) =>
          state['state'] == 'paused' &&
          ((state['position'] as num? ?? 0) - 3).abs() < 0.3,
    );
    await owner.call('volume', {'value': -12});
    _expect(
      ((await owner.snapshot())['volume'] as num) == -12,
      'Volume was not set in decibels.',
    );
    await owner.call('volume', {'value': volumeFloor});
    _expect(
      (await owner.snapshot())['volume'] == volumeFloor,
      'The configured volume floor was not accepted.',
    );
    await owner.call('volume', {'value': -12});
    await owner.call('eq', {'name': 'Rock'});
    _expect(
      (await owner.snapshot())['eq_preset'] == 'Rock',
      'EQ preset was not applied.',
    );
    await owner.call('eq', {'band': 3, 'value': 4.5});
    final equalized = await owner.snapshot();
    _expect(
      ((equalized['eq_bands'] as List)[3] as num) == 4.5,
      'The custom EQ band was not applied.',
    );
    await owner.call('play');
    await _waitForSnapshot(
      owner,
      'resume',
      (state) => state['state'] == 'playing',
    );
    await owner.call('pause');
    stdout.writeln(
      'PASS: WAV decode, play, pause, resume, seek, volume, and EQ.',
    );

    await _waitUntil('runtime job events and spectrum frames', () {
      return events.any((event) => event['event'] == 'runtime.job') &&
          events.any((event) => event['event'] == 'runtime.playback') &&
          frames.any((frame) => frame.isNotEmpty);
    });
    _expect(streamErrors.isEmpty, 'Stream errors: $streamErrors');
    _expect(
      frames.every((frame) => frame.every((value) => value.isFinite)),
      'Spectrum frames contain invalid numeric values.',
    );
    stdout.writeln(
      'PASS: real runtime event subscription and spectrum stream.',
    );

    await _desktopFeatures(owner, root, wav, environment);

    final attached = CliampBackend(
      executable: binary,
      environment: environment,
      processLauncher: launch,
    );
    backends.add(attached);
    subscriptions.add(
      attached.events.listen(
        (_) {},
        onError: (Object error) => streamErrors.add(error),
      ),
    );
    await attached.connect();
    _expect(
      children.where((child) => child.isDaemon).length == 1,
      'Attaching to a running player started another daemon.',
    );
    _expect(
      (await attached.snapshot())['total'] == 1,
      'The second adapter did not attach to the same queue.',
    );
    await attached.close();
    _expect(!daemon.exited, 'Closing an attached adapter killed the daemon.');
    _expect(
      (await owner.snapshot())['total'] == 1,
      'The owned player stopped responding after detaching a client.',
    );
    stdout.writeln('PASS: closing an attached client preserves the owner.');

    final setup = await owner.setupSchema('');
    _expect(
      (setup['providers'] as List).any(
        (provider) => provider is Map && provider['key'] == 'spotify',
      ),
      'The setup catalog does not include Spotify.',
    );
    final spotify = await owner.setupSchema('spotify');
    final picker = spotify['picker'] as Map;
    _expect(
      (picker['options'] as List).any(
        (option) => option is Map && option['value'] == 'default',
      ),
      'Spotify setup must offer the built-in client option.',
    );
    // The built-in app option needs no user credentials or network access.
    final builtIn = await owner.setupSchema('spotify', {
      picker['key'] as String: 'default',
    });
    final setupValues = Map<String, String>.from(builtIn['values'] as Map);
    _expect(
      setupValues['bitrate'] == '320',
      'Spotify setup did not return its supported bitrate default.',
    );
    final saved = await owner.saveProvider('spotify', setupValues);
    _expect(
      saved['ok'] == true && saved['restart_required'] == true,
      'Provider setup did not report saved configuration.',
    );
    _expect(
      !daemon.exited && owner.ownsDaemon,
      'Saving provider settings must not restart playback automatically.',
    );
    await owner.restartOwnedEngine();
    final previousExit = await daemon.exitCode;
    _expect(
      previousExit == 0,
      'Restart did not shut down the previous daemon gracefully.',
    );
    _expect(
      children.where((child) => child.isDaemon).length == 2,
      'Restart must launch exactly one replacement daemon.',
    );
    daemon = children.lastWhere((child) => child.isDaemon);
    _expect(
      owner.ownsDaemon && !daemon.exited,
      'The restarted engine is not owned or running.',
    );
    final providers = await owner.call('provider.list');
    _expect(
      (providers['providers'] as List).any(
        (provider) => provider is Map && provider['key'] == 'spotify',
      ),
      'Restarted engine did not register the configured Spotify provider.',
    );
    // Runtime volume operations are transient in cliamp. Restart restores the
    // configured startup volume, which provider setup must leave intact.
    _expect(
      (await owner.snapshot())['volume'] == initial['volume'],
      'Provider setup or restart overwrote the configured startup volume.',
    );
    stdout.writeln(
      'PASS: provider setup over stdin, preserved settings, and owned restart.',
    );

    await owner.close();
    final daemonExit = await daemon.exitCode.timeout(
      const Duration(seconds: 5),
    );
    _expect(
      daemonExit == 0,
      'The owned daemon must save state and exit gracefully (exit $daemonExit).',
    );
    final probe = await Process.run(
      binary!,
      ['remote', 'state'],
      environment: environment,
      runInShell: false,
    );
    _expect(
      probe.exitCode != 0 &&
          '${probe.stderr}'.contains('cliamp is not running'),
      'Closing the owner left a running IPC instance: ${probe.stdout}',
    );
    await _waitUntil(
      'all adapter subprocesses to exit',
      () => children.every((child) => child.exited),
    );
    _expect(streamErrors.isEmpty, 'Stream errors: $streamErrors');
    stdout.writeln('PASS: closing the owner stops its daemon and all clients.');
  } finally {
    // Retain real process handles independently of the adapter so even a
    // lifecycle assertion failure cannot leave the test daemon behind.
    for (final backend in backends.reversed) {
      try {
        await backend.close().timeout(const Duration(seconds: 5));
      } catch (error) {
        stderr.writeln('Adapter cleanup: $error');
      }
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final child in children.where((child) => !child.exited)) {
      child.kill();
      try {
        await child.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 2));
      }
    }
    await root.delete(recursive: true);
  }
}

Future<void> _desktopFeatures(
  CliampBackend backend,
  Directory root,
  File wav,
  Map<String, String> environment,
) async {
  final second = await wav.copy('${root.path}/Second track.wav');
  final beforeFailure = await backend.snapshot();
  await _mustFail(
    () => backend.call('sources.load', {
      'args': [wav.path, '${root.path}/missing.wav'],
      'name': 'append',
      'if_revision': beforeFailure['playlist_revision'],
    }),
    'A missing source must reject the whole source batch.',
  );
  _expect(
    (await backend.snapshot())['total'] == beforeFailure['total'],
    'Failed source resolution partially appended tracks.',
  );
  await backend.call('sources.load', {
    'args': [wav.path, second.path],
    'name': 'replace',
    'if_revision': beforeFailure['playlist_revision'],
  });
  final batchState = await backend.snapshot();
  _expect(batchState['total'] == 2, 'Source batch did not replace the queue.');
  await backend.call('queue.remove_many', {
    'indexes': [0, 1],
    'if_revision': batchState['playlist_revision'],
  });
  _expect(
    ((await backend.snapshot())['total'] ?? 0) == 0,
    'Atomic removal did not remove both selected rows.',
  );
  await backend.call('queue.undo', {
    'if_revision': (await backend.snapshot())['playlist_revision'],
  });
  _expect(
    (await backend.snapshot())['total'] == 2,
    'Undo did not restore the whole removed batch.',
  );
  final saveQueue = <String, dynamic>{
    'provider': 'local',
    'playlist': 'Captured queue',
    'if_revision': (await backend.snapshot())['playlist_revision'],
  };
  await backend.call('playlist.save_queue', saveQueue);
  _expect(
    ((await backend.call('provider.tracks', {
                  'provider': 'local',
                  'playlist': 'Captured queue',
                }))['tracks']
                as List)
            .length ==
        2,
    'Saving the current queue did not capture its tracks.',
  );
  await _mustFail(
    () => backend.call('playlist.save_queue', saveQueue),
    'Saving the current queue must not overwrite an existing playlist.',
  );
  const target = {'provider': 'local', 'playlist': 'Desktop regression'};
  final zulu = {
    'path': wav.path,
    'title': 'Zulu',
    'provider_meta': {'test.id': 'z'},
  };
  final alpha = {'path': second.path, 'title': 'Alpha'};
  await backend.call('playlist.create', target);
  await backend.call('playlist.replace', {
    ...target,
    'tracks': [zulu, alpha],
  });
  Future<List<dynamic>> savedTracks() async =>
      (await backend.call('provider.tracks', target))['tracks'] as List;
  await backend.call('playlist.sort', {...target, 'sort': 'title'});
  _expect(
    (await savedTracks()).first['title'] == 'Alpha',
    'Saved playlist sort did not order the full playlist.',
  );
  await backend.call('playlist.move', {
    ...target,
    'index': 0,
    'to': 1,
    'track': alpha,
  });
  _expect(
    (await savedTracks()).first['title'] == 'Zulu',
    'Saved playlist move did not use the guarded row.',
  );
  await backend.call('playlist.undo', target);
  _expect(
    (await savedTracks()).first['title'] == 'Alpha',
    'Saved playlist undo did not restore ordering.',
  );
  await backend.call('playlist.prepend', {
    ...target,
    'tracks': [zulu],
  });
  final prepended = await savedTracks();
  _expect(
    prepended.length == 2 && prepended.first['title'] == 'Zulu',
    'Prepending an existing track duplicated it or lost its order.',
  );
  _expect(
    (prepended.first['provider_meta'] as Map)['test.id'] == 'z',
    'Saved playlist mutations lost provider metadata.',
  );
  final third = await wav.copy('${root.path}/Saved import one.wav');
  final fourth = await wav.copy('${root.path}/Saved import two.wav');
  final beforeImport = await backend.snapshot();
  final liveBeforeImport = (await backend.call('queue.list'))['tracks'];
  await _mustFail(
    () => backend.call('playlist.import', {
      ...target,
      'args': [third.path, '${root.path}/missing import.wav'],
    }),
    'A missing saved-playlist source must reject the whole import.',
  );
  _expect(
    jsonEncode(await savedTracks()) == jsonEncode(prepended),
    'Failed saved-playlist import partially changed the saved document.',
  );
  await backend.call('playlist.import', {
    ...target,
    'args': [third.path, fourth.path],
  });
  final imported = await savedTracks();
  _expect(
    imported.length == 4 &&
        imported[2]['path'] == third.path &&
        imported[3]['path'] == fourth.path,
    'Native file import did not append the complete selection in order.',
  );
  final afterImport = await backend.snapshot();
  _expect(
    afterImport['playlist_revision'] == beforeImport['playlist_revision'] &&
        afterImport['index'] == beforeImport['index'] &&
        jsonEncode((await backend.call('queue.list'))['tracks']) ==
            jsonEncode(liveBeforeImport),
    'Saved-playlist import changed the live queue or selected track.',
  );
  await backend.call('playlist.undo', target);
  _expect(
    jsonEncode(await savedTracks()) == jsonEncode(prepended),
    'Undo did not restore saved order and metadata after native import.',
  );
  final music = await Directory('${root.path}/directory music').create();
  final nested = await Directory('${music.path}/nested').create();
  await wav.copy('${music.path}/Top.wav');
  await wav.copy('${nested.path}/Nested.wav');
  const directories = {'provider': 'local', 'playlist': 'Directory regression'};
  await backend.call('playlist.create', directories);
  await backend.call('playlist.dirs.add', {...directories, 'path': music.path});
  await backend.call('playlist.dirs.recursive', {
    ...directories,
    'path': music.path,
    'name': 'off',
  });
  _expect(
    ((await backend.call('provider.tracks', directories))['tracks'] as List)
            .length ==
        1,
    'Nonrecursive directory source included nested files.',
  );
  await backend.call('playlist.dirs.recursive', {
    ...directories,
    'path': music.path,
    'name': 'on',
  });
  _expect(
    ((await backend.call('provider.tracks', directories))['tracks'] as List)
            .length ==
        2,
    'Recursive directory source missed nested files.',
  );
  await backend.call('playlist.dirs.remove', {
    ...directories,
    'path': music.path,
  });
  _expect(
    ((await backend.call('playlist.dirs.list', directories))['directories']
            as List)
        .isEmpty,
    'Directory source removal did not persist.',
  );
  await backend.call('playlist.undo', directories);
  final restored =
      (await backend.call('playlist.dirs.list', directories))['directories']
          as List;
  _expect(
    restored.length == 1 && restored.single['recursive'] == true,
    'Undo did not restore the directory source document and recursive mode.',
  );
  stdout.writeln(
    'PASS: atomic sources, batch removal/undo, saved order, and directory sources.',
  );
  await backend.call('lyrics.offset', {'value': 250});
  _expect(
    (await backend.snapshot())['lyrics_offset_ms'] == 250 &&
        (await backend.call('lyrics.offset'))['offset_ms'] == 250,
    'Lyrics offset was not reflected in snapshots and direct reads.',
  );
  await backend.call('lyrics.offset', {'value': 0});
  final jobsBeforeFrames = backend.currentJobs.length;
  final frame = await backend.readFrame(80, 24);
  _expect(
    frame['frame'] is String,
    'Direct visualizer frame returned no ANSI text.',
  );
  _expect(
    backend.currentJobs.length == jobsBeforeFrames,
    'Direct visualizer reads must not create operation jobs.',
  );
  final preferences = await backend.preferencesSchema();
  final originalValues = preferences['values'] as Map;
  final themes =
      (await backend.call('desktop.theme', {'name': 'list'}))['items'] as List;
  _expect(themes.length > 1, 'No alternative theme is available for preview.');
  await backend.call('desktop.theme.preview', {'name': themes[1]});
  _expect(
    ((await backend.snapshot())['theme'] as Map)['name'] == themes[1],
    'Theme preview did not change the runtime theme.',
  );
  _expect(
    ((await backend.preferencesSchema())['values'] as Map)['theme'] ==
        originalValues['theme'],
    'Theme preview wrote persistent preferences.',
  );
  await backend.call('desktop.theme.preview', {
    'name': originalValues['theme'] == '' ? 'default' : originalValues['theme'],
  });
  final modes = await backend.call('desktop.vis', {'name': 'list'});
  final modeIndex = modes['index'] as int? ?? 0;
  await backend.call('desktop.vis.preview', {'index': modeIndex == 0 ? 1 : 0});
  _expect(
    ((await backend.preferencesSchema())['values'] as Map)['visualizer'] ==
        originalValues['visualizer'],
    'Visualizer preview wrote persistent preferences.',
  );
  await backend.call('desktop.vis.preview', {'index': modeIndex});
  _expect(
    (preferences['values'] as Map)['volume_min'] == '-65',
    'Preference schema lost the configured audio floor.',
  );
  final changed = await backend.savePreferences({
    'downloads.directory': '${root.path}/downloads',
    'buffer_ms': '300',
  });
  _expect(
    changed['restart_required'] == true,
    'Preference updates must describe the restart requirement.',
  );
  final afterPreferences = (await backend.preferencesSchema())['values'] as Map;
  _expect(
    afterPreferences['buffer_ms'] == '300' &&
        afterPreferences['downloads.directory'] == '${root.path}/downloads' &&
        afterPreferences['volume_min'] == '-65',
    'Preferences did not persist or overwrote unrelated settings.',
  );
  final plugins = await Directory(
    '${environment['CLIAMP_CONFIG_DIR']}/plugins',
  ).create(recursive: true);
  const pluginCode =
      'plugin.register({name="Smoke",type="hook",permissions={}})\n';
  await File('${plugins.path}/smoke.lua').writeAsString(pluginCode);
  final review =
      (await backend.pluginAction('review', {'name': 'smoke'}))['review']
          as Map;
  _expect(
    review['code'] == pluginCode && (review['sha256'] as String).length == 64,
    'Plugin review must expose exactly the fixture code and digest.',
  );
  final approval = <String, dynamic>{
    'token': review['token'],
    'source': review['source'],
    'sha256': review['sha256'],
    'permissions': review['permissions'],
  };
  await _mustFail(
    () => backend.pluginAction('trust', {...approval, 'sha256': '0' * 64}),
    'Plugin trust must reject an altered review digest.',
  );
  await backend.pluginAction('trust', approval);
  var installed = (await backend.pluginAction('list'))['plugins'] as List;
  _expect(
    installed.single['trust'] == 'trusted',
    'Reviewed plugin was not trusted.',
  );
  await backend.pluginAction('configure', {
    'name': 'smoke',
    'values': {'enabled': 'false', 'label': 'fixture-only'},
  });
  installed = (await backend.pluginAction('list'))['plugins'] as List;
  _expect(
    installed.single['enabled'] == false &&
        (installed.single['config_keys'] as List).contains('label') &&
        !jsonEncode(installed).contains('fixture-only'),
    'Plugin list must show configuration keys while keeping values private.',
  );
  await backend.pluginAction('remove', {'name': 'smoke'});
  _expect(
    ((await backend.pluginAction('list'))['plugins'] as List).isEmpty,
    'Plugin removal left the fixture installed.',
  );
  stdout.writeln(
    'PASS: lyrics timing, direct frames, preferences, and reviewed offline plugin trust.',
  );
  await backend.call('tracks.replace', {
    'tracks': [
      {'path': wav.path},
    ],
    'if_revision': (await backend.snapshot())['playlist_revision'],
  });
}

Future<void> _mustFail(
  Future<dynamic> Function() action,
  String message,
) async {
  try {
    await action();
  } on BackendException {
    return;
  }
  throw StateError(message);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _waitUntil(String description, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for $description.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<Map<String, dynamic>> _waitForSnapshot(
  PlayerBackend backend,
  String description,
  bool Function(Map<String, dynamic>) ready,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (true) {
    final state = await backend.snapshot();
    if (ready(state)) return state;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Timed out waiting for $description. Last state: ${jsonEncode(state)}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

// A 20-second, mono PCM WAV needs no FFmpeg, network, or fixture download.
Uint8List _wave() {
  const sampleRate = 22050;
  const samples = sampleRate * 20;
  final bytes = Uint8List(44 + samples * 2);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var sample = 0; sample < samples; sample++) {
    data.setInt16(
      44 + sample * 2,
      (math.sin(2 * math.pi * 440 * sample / sampleRate) * 800).round(),
      Endian.little,
    );
  }
  return bytes;
}

class _TrackedProcess implements InputBackendProcess {
  _TrackedProcess(this.process, this.arguments) {
    unawaited(process.exitCode.then((_) => exited = true));
  }
  final Process process;
  final List<String> arguments;
  bool exited = false;
  bool get isDaemon => arguments.length == 1 && arguments.single == '--daemon';
  @override
  Stream<List<int>> get stdout => process.stdout;
  @override
  Stream<List<int>> get stderr => process.stderr;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      process.kill(signal);
  @override
  Future<void> writeInput(String input) async {
    process.stdin.write(input);
    await process.stdin.close();
  }
}
