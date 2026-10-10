import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cliamp_desktop/src/backend.dart';
import 'package:cliamp_desktop/src/jobs.dart';
import 'package:cliamp_desktop/src/provider_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> envelope(Map<String, dynamic> fields) => {
  'version': 2,
  'ok': true,
  ...fields,
};

class FakeProcess implements BackendProcess {
  FakeProcess();
  FakeProcess.json(Map<String, dynamic> value) {
    finish(output: jsonEncode(value));
  }
  FakeProcess.failure(String message, [int code = 1]) {
    finish(error: message, code: code);
  }

  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool killed = false;
  bool get isRunning => !_exit.isCompleted;

  void line(Map<String, dynamic> value) {
    _stdout.add(utf8.encode('${jsonEncode(value)}\n'));
  }

  void finish({String output = '', String error = '', int code = 0}) {
    if (_exit.isCompleted) return;
    if (output.isNotEmpty) _stdout.add(utf8.encode(output));
    if (error.isNotEmpty) _stderr.add(utf8.encode(error));
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_exit.isCompleted) return false;
    killed = true;
    finish(code: -1);
    return true;
  }
}

class FakeInputProcess extends FakeProcess implements InputBackendProcess {
  FakeInputProcess(this.respond);
  final void Function(FakeInputProcess process, String input) respond;
  String? receivedInput;

  @override
  Future<void> writeInput(String input) async {
    receivedInput = input;
    respond(this, input);
  }
}

class FakeLauncher {
  final commands = <List<String>>[];
  final executables = <String>[];
  final environments = <Map<String, String>>[];
  final eventProcesses = <FakeProcess>[];
  final spectrumProcesses = <FakeProcess>[];
  final daemons = <FakeProcess>[];
  FakeProcess? Function(List<String> arguments)? onCommand;
  int stateReads = 0;

  Future<BackendProcess> launch(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    commands.add(List.of(arguments));
    executables.add(executable);
    environments.add(Map.of(environment));
    final custom = onCommand?.call(arguments);
    if (custom != null) return custom;
    if (arguments.first == '--daemon') {
      final process = FakeProcess();
      daemons.add(process);
      return process;
    }
    if (arguments.first == 'visstream') {
      final process = FakeProcess();
      spectrumProcesses.add(process);
      return process;
    }
    if (arguments[1] == 'events') {
      final process = FakeProcess();
      eventProcesses.add(process);
      return process;
    }
    if (arguments[1] == 'state') {
      stateReads++;
      return FakeProcess.json(
        envelope({
          'snapshot': {
            'state': 'stopped',
            'revision': stateReads,
            'playlist_revision': 2,
            'index': -1,
          },
        }),
      );
    }
    if (arguments[1] == 'capabilities') {
      return FakeProcess.json(
        envelope({
          'result': [
            {'name': 'play', 'description': 'Start playback'},
          ],
        }),
      );
    }
    if (arguments.contains('desktop.quit')) {
      for (final daemon in daemons) {
        daemon.finish();
      }
    }
    return FakeProcess.json(
      envelope({
        'job': {
          'id': 'job-1',
          'state': 'succeeded',
          'result': {
            'ok': true,
            'items': ['done'],
          },
          'snapshot': {'state': 'playing', 'revision': 9},
        },
      }),
    );
  }

  CliampBackend backend({
    Duration commandTimeout = const Duration(seconds: 1),
    Duration startupTimeout = const Duration(seconds: 1),
    Duration shutdownTimeout = const Duration(milliseconds: 20),
  }) => CliampBackend(
    executable: '/test/cliamp',
    processLauncher: launch,
    commandTimeout: commandTimeout,
    startupTimeout: startupTimeout,
    shutdownTimeout: shutdownTimeout,
    refreshInterval: const Duration(hours: 1),
    reconnectDelay: const Duration(milliseconds: 5),
  );
}

class WidgetJobsBackend implements JobProgressBackend {
  final changes = StreamController<List<BackendJob>>.broadcast();
  final canceled = <String>[];
  @override
  List<BackendJob> currentJobs = [
    BackendJob(
      id: 'visible-job',
      operation: 'provider.auth',
      state: 'running',
      createdAt: DateTime.now(),
    ),
  ];
  @override
  Stream<List<BackendJob>> get jobs => changes.stream;
  @override
  Future<void> cancelJob(String jobId) async {
    canceled.add(jobId);
    currentJobs = [
      currentJobs.single.copyWith(state: 'canceled', cancellable: false),
    ];
    changes.add(currentJobs);
  }
}

class SignInBackend extends WidgetJobsBackend implements PlayerBackend {
  SignInBackend({this.supportsCancellation = true}) {
    currentJobs = [];
  }
  final bool supportsCancellation;
  final authResult = Completer<Map<String, dynamic>>();
  String authState = 'idle';
  @override
  Future<void> connect() async {}
  @override
  Future<Map<String, dynamic>> snapshot() async => {};
  @override
  Future<Map<String, dynamic>> capabilities() async => {};
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Stream<List<double>> get spectrum => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (operation == 'provider.auth.status') {
      return {
        'ok': true,
        'auth': {
          'provider': 'remote',
          'state': authState,
          'cancellable': supportsCancellation,
          if (authState == 'authenticating')
            'url': 'https://example.test/sign-in',
        },
      };
    }
    authState = 'authenticating';
    currentJobs = [
      BackendJob(
        id: 'auth-dialog-job',
        operation: 'provider.auth',
        provider: 'remote',
        state: 'running',
        createdAt: DateTime.now(),
        cancellable: supportsCancellation,
      ),
    ];
    changes.add(currentJobs);
    return authResult.future;
  }

  @override
  Future<void> cancelJob(String jobId) async {
    await super.cancelJob(jobId);
    authState = 'canceled';
    authResult.completeError(
      const BackendException('job canceled', code: 'canceled'),
    );
  }
}

Future<void> eventually(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Condition did not become true');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test(
    'attaches to an existing engine and only closes its client processes',
    () async {
      final runner = FakeLauncher();
      final backend = runner.backend();
      await Future.wait([backend.connect(), backend.connect()]);
      await eventually(() => runner.eventProcesses.isNotEmpty);
      expect(runner.stateReads, 1);
      expect(runner.daemons, isEmpty);
      expect((await backend.snapshot())['index'], -1);
      await backend.close();
      expect(
        runner.commands.where((args) => args.contains('desktop.quit')),
        isEmpty,
      );
      expect(runner.eventProcesses.every((process) => process.killed), isTrue);
      expect(
        runner.spectrumProcesses.every((process) => process.killed),
        isTrue,
      );
    },
  );

  test('starts and owns a daemon only when the socket is absent', () async {
    final runner = FakeLauncher();
    runner.onCommand = (arguments) {
      if (arguments.length > 1 &&
          arguments[1] == 'state' &&
          runner.daemons.isEmpty) {
        return FakeProcess.failure(
          'cliamp is not running (no socket at /tmp/x)',
        );
      }
      return null;
    };
    final backend = runner.backend();
    await backend.connect();
    expect(runner.daemons, hasLength(1));
    expect(runner.daemons.single.killed, isFalse);
    await Future.wait([backend.close(), backend.close()]);
    expect(runner.daemons.single.killed, isFalse);
    expect(
      runner.commands.where((args) => args.contains('desktop.quit')),
      hasLength(1),
    );
  });

  for (final failure in ['unsupported', 'stalled client', 'stalled daemon']) {
    test('owned daemon shutdown falls back safely when $failure', () async {
      final runner = FakeLauncher();
      final quitClient = switch (failure) {
        'unsupported' => FakeProcess.failure('unknown operation: desktop.quit'),
        'stalled client' => FakeProcess(),
        _ => FakeProcess.json(
          envelope({
            'job': {'id': 'quit-job', 'state': 'queued'},
          }),
        ),
      };
      runner.onCommand = (arguments) {
        if (arguments.length > 1 &&
            arguments[1] == 'state' &&
            runner.daemons.isEmpty) {
          return FakeProcess.failure(
            'cliamp is not running (no socket at /tmp/x)',
          );
        }
        if (arguments.contains('desktop.quit')) return quitClient;
        return null;
      };
      final backend = runner.backend();
      await backend.connect();
      final closing = backend.close();
      await expectLater(
        backend.call('play'),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            'closed',
          ),
        ),
      );
      await closing;
      expect(runner.daemons.single.killed, isTrue);
      if (failure == 'stalled client') expect(quitClient.killed, isTrue);
      expect(
        runner.commands.where((args) => args.contains('desktop.quit')),
        hasLength(1),
      );
    });
  }

  test(
    'a permission error is reported without launching a second daemon',
    () async {
      final runner = FakeLauncher();
      runner.onCommand = (_) =>
          FakeProcess.failure('connect: permission denied');
      final backend = runner.backend();
      addTearDown(backend.close);
      await expectLater(
        backend.connect(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'message',
            contains('permission denied'),
          ),
        ),
      );
      expect(runner.daemons, isEmpty);
      expect(runner.commands, hasLength(1));
    },
  );

  test('startup failures retain the daemon diagnostic', () async {
    final runner = FakeLauncher();
    runner.onCommand = (arguments) {
      if (arguments.first == '--daemon') {
        return FakeProcess.failure('audio device could not open', 2);
      }
      return FakeProcess.failure('cliamp is not running (no socket at /tmp/x)');
    };
    final backend = runner.backend();
    addTearDown(backend.close);
    await expectLater(
      backend.connect(),
      throwsA(
        isA<BackendException>()
            .having((e) => e.code, 'code', 'startup_failed')
            .having((e) => e.message, 'message', contains('audio device')),
      ),
    );
  });

  test(
    'startup has a deadline and terminates an unready owned daemon',
    () async {
      final runner = FakeLauncher();
      runner.onCommand = (arguments) => arguments.first == '--daemon'
          ? null
          : FakeProcess.failure('cliamp is not running (no socket at /tmp/x)');
      final backend = runner.backend(
        startupTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(backend.close);
      await expectLater(
        backend.connect(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            'startup_timeout',
          ),
        ),
      );
      expect(runner.daemons.single.killed, isTrue);
    },
  );

  test('unwraps capability metadata and a terminal operation result', () async {
    final runner = FakeLauncher();
    final backend = runner.backend();
    addTearDown(backend.close);
    final received = <Map<String, dynamic>>[];
    final subscription = backend.events.listen(received.add);
    addTearDown(subscription.cancel);
    final capabilities = await backend.capabilities();
    expect((capabilities['operations'] as List).single['name'], 'play');
    expect(await backend.call('play'), {
      'ok': true,
      'items': ['done'],
    });
    await eventually(
      () => received.any((event) => event['data']['revision'] == 9),
    );
  });

  test('polls queued jobs and submits a mutation only once', () async {
    final runner = FakeLauncher();
    var polls = 0;
    runner.onCommand = (arguments) {
      if (arguments.length < 2) return null;
      if (arguments[1] == 'call' || arguments[1] == 'job') {
        if (arguments[1] == 'job') polls++;
        return FakeProcess.json(
          envelope({
            'job': {
              'id': 'slow-job',
              'state': polls == 2
                  ? 'succeeded'
                  : polls == 1
                  ? 'running'
                  : 'queued',
              if (polls == 2) 'result': {'ok': true, 'total': 3},
            },
          }),
        );
      }
      return null;
    };
    final backend = runner.backend();
    addTearDown(backend.close);
    expect(await backend.call('provider.tracks', {'provider': 'local'}), {
      'ok': true,
      'total': 3,
    });
    expect(polls, 2);
    expect(
      runner.commands.where((args) => args.contains('call')),
      hasLength(1),
    );
  });

  test(
    'propagates revision conflicts and never retries the mutation',
    () async {
      final runner = FakeLauncher();
      runner.onCommand = (arguments) {
        if (arguments.length > 1 && arguments[1] == 'call') {
          return FakeProcess.json(
            envelope({
              'job': {
                'id': 'conflicted',
                'state': 'failed',
                'error': {
                  'code': 'conflict',
                  'message':
                      'operation cannot be performed in the current state',
                  'detail': 'playlist revision changed',
                },
              },
            }),
          );
        }
        return null;
      };
      final backend = runner.backend();
      addTearDown(backend.close);
      await expectLater(
        backend.call('queue.remove', {'index': 0, 'if_revision': 1}),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'conflict')
              .having(
                (e) => e.message,
                'message',
                contains('playlist revision changed'),
              ),
        ),
      );
      expect(
        runner.commands.where((args) => args.contains('call')),
        hasLength(1),
      );
    },
  );

  test('passes hostile path characters as a single JSON argument', () async {
    final runner = FakeLauncher();
    final backend = CliampBackend(
      environment: {'CLIAMP_BINARY': '/opt/Player App/cliamp'},
      processLauncher: runner.launch,
    );
    addTearDown(backend.close);
    const path = '/music/a "quoted" song; \$(touch nope).flac';
    await backend.call('queue', {'path': path});
    final arguments = runner.commands.singleWhere(
      (args) => args.contains('call'),
    );
    expect(arguments, hasLength(5));
    expect(jsonDecode(arguments[3]), {'path': path});
    expect(runner.executables.toSet(), {'/opt/Player App/cliamp'});
    expect(
      runner.environments.every(
        (value) => value['CLIAMP_BINARY'] == '/opt/Player App/cliamp',
      ),
      isTrue,
    );
  });

  test(
    'resynchronizes after an overflow before opening replacement streams',
    () async {
      final runner = FakeLauncher();
      final backend = runner.backend();
      addTearDown(backend.close);
      final received = <Map<String, dynamic>>[];
      final errors = <Object>[];
      final subscription = backend.events.listen(
        received.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);
      await backend.connect();
      await eventually(() => runner.eventProcesses.isNotEmpty);
      runner.eventProcesses.single.line({
        'event': 'system.overflow',
        'data': {'resync_required': true},
      });
      await eventually(() => runner.eventProcesses.length == 2);
      expect(errors.single, isA<BackendException>());
      expect(runner.eventProcesses.first.killed, isTrue);
      expect(received.last['event'], 'runtime.state');
      expect(received.last['data']['revision'], 2);
      final lastState = runner.commands.lastIndexWhere(
        (args) => args.contains('state'),
      );
      final lastEvents = runner.commands.lastIndexWhere(
        (args) => args.contains('events'),
      );
      expect(lastState, lessThan(lastEvents));
    },
  );

  test(
    'subscribes to and forwards transient provider sign-in updates',
    () async {
      final runner = FakeLauncher();
      final backend = runner.backend();
      addTearDown(backend.close);
      final authUpdate = backend.events.firstWhere(
        (event) => event['event'] == 'provider.auth',
      );
      await backend.connect();
      await eventually(() => runner.eventProcesses.isNotEmpty);
      final arguments = runner.commands.singleWhere(
        (args) => args.contains('events'),
      );
      expect(arguments, contains('provider.auth'));
      final update = {
        'event': 'provider.auth',
        'data': {
          'ok': true,
          'auth': {
            'provider': 'spotify',
            'state': 'authenticating',
            'url': 'https://accounts.spotify.com/authorize?state=test',
          },
        },
      };
      runner.eventProcesses.single.line(update);
      expect(await authUpdate, update);
    },
  );

  test('decodes spectrum frames as doubles', () async {
    final runner = FakeLauncher();
    final backend = runner.backend();
    addTearDown(backend.close);
    final frame = backend.spectrum.first;
    await backend.connect();
    await eventually(() => runner.spectrumProcesses.isNotEmpty);
    runner.spectrumProcesses.single.line({
      'ok': true,
      'bands': [0, 0.2, 1],
    });
    expect(await frame, [0.0, 0.2, 1.0]);
  });

  test('bounds command waits and closes the hung client', () async {
    final runner = FakeLauncher();
    final hung = FakeProcess();
    runner.onCommand = (arguments) =>
        arguments.length > 1 && arguments[1] == 'capabilities' ? hung : null;
    final backend = runner.backend(
      commandTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(backend.close);
    await expectLater(
      backend.capabilities(),
      throwsA(isA<BackendException>().having((e) => e.code, 'code', 'timeout')),
    );
    expect(hung.killed, isTrue);
  });

  test('rejects unsupported protocol versions', () async {
    final runner = FakeLauncher();
    runner.onCommand = (_) => FakeProcess.json({'version': 1, 'ok': true});
    final backend = runner.backend();
    addTearDown(backend.close);
    await expectLater(
      backend.connect(),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          'code',
          'invalid_version',
        ),
      ),
    );
    expect(runner.daemons, isEmpty);
  });

  test('close is idempotent and prevents starting new processes', () async {
    final runner = FakeLauncher();
    final backend = runner.backend();
    await backend.close();
    await backend.close();
    await expectLater(
      backend.call('play'),
      throwsA(isA<BackendException>().having((e) => e.code, 'code', 'closed')),
    );
    expect(runner.commands, isEmpty);
  });

  test(
    'reads provider lists and conditional schemas without starting audio',
    () async {
      final runner = FakeLauncher();
      final inputs = <Map<String, dynamic>>[];
      runner.onCommand = (arguments) {
        expect(arguments.take(2), ['setup', 'schema']);
        return FakeInputProcess((process, input) {
          inputs.add(jsonDecode(input) as Map<String, dynamic>);
          process.finish(
            output: jsonEncode({
              'ok': true,
              'providers': [
                {'key': 'navidrome', 'name': 'Navidrome'},
              ],
              if (arguments.contains('--provider')) ...{
                'provider': 'navidrome',
                'fields': [
                  {'key': 'password', 'secret': true, 'value': ''},
                ],
                'values': {'server': inputs.last['server']},
              },
            }),
          );
        });
      };
      final backend = runner.backend();
      addTearDown(backend.close);
      final providers = await backend.setupSchema('');
      expect((providers['providers'] as List).single['key'], 'navidrome');
      final schema = await backend.setupSchema('navidrome', {
        'server': 'https://music.example.test',
      });
      expect(schema['values'], {'server': 'https://music.example.test'});
      expect(inputs, [
        {},
        {'server': 'https://music.example.test'},
      ]);
      expect(runner.commands.first, ['setup', 'schema']);
      expect(runner.commands.last, [
        'setup',
        'schema',
        '--provider',
        'navidrome',
      ]);
      expect(runner.daemons, isEmpty);
      expect(runner.stateReads, 0);
    },
  );

  test('saves provider secrets only through stdin', () async {
    final runner = FakeLauncher();
    const secret = 'a private value; \$(touch ignored) "quote"';
    final process = FakeInputProcess((process, input) {
      process.finish(
        output: jsonEncode({'ok': true, 'restart_required': true}),
      );
    });
    runner.onCommand = (_) => process;
    final backend = runner.backend();
    addTearDown(backend.close);
    expect(await backend.saveProvider('navidrome', {'password': secret}), {
      'ok': true,
      'restart_required': true,
    });
    expect(jsonDecode(process.receivedInput!), {'password': secret});
    expect(runner.commands.single, [
      'setup',
      'apply',
      '--provider',
      'navidrome',
    ]);
    expect(
      runner.commands.expand((args) => args).join(' '),
      isNot(contains(secret)),
    );
    expect(runner.environments.single.values, isNot(contains(secret)));
  });

  test(
    'skips the provider connection check only when explicitly requested',
    () async {
      final runner = FakeLauncher();
      runner.onCommand = (_) => FakeInputProcess((process, input) {
        process.finish(
          output: jsonEncode({'ok': true, 'restart_required': true}),
        );
      });
      final backend = runner.backend();
      addTearDown(backend.close);
      await backend.saveProvider('navidrome', {
        'server': 'https://music.example.test',
      });
      expect(runner.commands.last, isNot(contains('--save-without-check')));
      await backend.saveProvider('navidrome', {
        'server': 'https://music.example.test',
      }, verifyConnection: false);
      expect(runner.commands.last, [
        'setup',
        'apply',
        '--provider',
        'navidrome',
        '--save-without-check',
      ]);
    },
  );

  test(
    'allows provider probes longer than the normal command timeout',
    () async {
      final runner = FakeLauncher();
      runner.onCommand = (_) => FakeInputProcess((process, input) {
        Timer(const Duration(milliseconds: 30), () {
          process.finish(
            output: jsonEncode({'ok': true, 'restart_required': true}),
          );
        });
      });
      final backend = CliampBackend(
        executable: '/test/cliamp',
        processLauncher: runner.launch,
        commandTimeout: const Duration(milliseconds: 10),
        operationTimeout: const Duration(seconds: 1),
      );
      addTearDown(backend.close);
      expect(await backend.saveProvider('navidrome', {}), {
        'ok': true,
        'restart_required': true,
      });
    },
  );

  for (final fromPipe in [false, true]) {
    test(
      'redacts setup ${fromPipe ? 'pipe failures' : 'command diagnostics'}',
      () async {
        final runner = FakeLauncher();
        const secret = 'secret-provider-password';
        runner.onCommand = (_) => FakeInputProcess((process, input) {
          if (fromPipe) {
            process.finish(code: 1);
            throw StateError('could not send $secret');
          }
          process.finish(
            code: 1,
            error: 'provider returned password=$secret',
            output: jsonEncode({
              'ok': false,
              'error': 'invalid password $secret',
            }),
          );
        });
        final backend = runner.backend();
        addTearDown(backend.close);
        await expectLater(
          backend.saveProvider('navidrome', {'password': secret}),
          throwsA(
            isA<BackendException>()
                .having((error) => error.code, 'code', 'setup_failed')
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains(secret)),
                ),
          ),
        );
      },
    );
  }

  test(
    'restarts only its owned daemon and keeps event subscriptions usable',
    () async {
      final runner = FakeLauncher();
      runner.onCommand = (arguments) {
        if (arguments.length > 1 &&
            arguments[1] == 'state' &&
            !runner.daemons.any((process) => process.isRunning)) {
          return FakeProcess.failure(
            'cliamp is not running (no socket at /tmp/x)',
          );
        }
        return null;
      };
      final backend = runner.backend();
      addTearDown(backend.close);
      final received = <Map<String, dynamic>>[];
      final subscription = backend.events.listen(received.add);
      addTearDown(subscription.cancel);
      await backend.connect();
      expect(backend.ownsDaemon, isTrue);
      await Future.wait([
        backend.restartOwnedEngine(),
        backend.restartOwnedEngine(),
      ]);
      expect(runner.daemons, hasLength(2));
      expect(runner.daemons.first.isRunning, isFalse);
      expect(runner.daemons.first.killed, isFalse);
      expect(runner.daemons.last.isRunning, isTrue);
      expect(backend.ownsDaemon, isTrue);
      await eventually(() => received.length >= 2);
      expect(await backend.call('play'), {
        'ok': true,
        'items': ['done'],
      });
    },
  );

  test('restart preserves every queue page and play-next order', () async {
    final runner = FakeLauncher();
    final tracks = List.generate(
      201,
      (index) => {
        'path': '/music/$index.wav',
        'index': index,
        'provider_meta': {'source': 'audit'},
      },
    );
    runner.onCommand = (args) {
      if (args.length > 1 &&
          args[1] == 'state' &&
          !runner.daemons.any((p) => p.isRunning)) {
        return FakeProcess.failure(
          'cliamp is not running (no socket at /tmp/x)',
        );
      }
      if (args.length > 1 &&
          args[1] == 'call' &&
          ['queue.list', 'playnext.list'].contains(args.last)) {
        final params = jsonDecode(args[args.indexOf('--params') + 1]) as Map;
        final rows = args.last == 'queue.list'
            ? tracks
            : [tracks[200], tracks[0]];
        return FakeProcess.json(
          envelope({
            'job': {
              'id': 'read',
              'state': 'succeeded',
              'result': {
                'tracks': rows.skip(params['offset'] as int).take(200).toList(),
                'total': rows.length,
              },
            },
          }),
        );
      }
      return null;
    };
    final backend = runner.backend();
    addTearDown(backend.close);
    await backend.connect();
    await backend.restartOwnedEngine();
    final append = runner.commands
        .where((args) => args.last == 'tracks.append')
        .map((args) => jsonDecode(args[args.indexOf('--params') + 1]) as Map)
        .toList();
    expect(append.map((p) => (p['tracks'] as List).length), [200, 1]);
    expect(append.expand((p) => p['tracks'] as List).toList(), tracks);
    final queued = runner.commands
        .where((args) => args.last == 'queue.enqueue')
        .map(
          (args) =>
              (jsonDecode(args[args.indexOf('--params') + 1]) as Map)['index'],
        )
        .toList();
    expect(queued, [200, 0]);
  });

  test('failed restart capture leaves the owned daemon running', () async {
    final runner = FakeLauncher();
    runner.onCommand = (args) {
      if (args.length > 1 &&
          args[1] == 'state' &&
          !runner.daemons.any((p) => p.isRunning)) {
        return FakeProcess.failure(
          'cliamp is not running (no socket at /tmp/x)',
        );
      }
      if (args.last == 'queue.list') {
        return FakeProcess.failure('unable to read queue');
      }
      return null;
    };
    final backend = runner.backend();
    addTearDown(backend.close);
    await backend.connect();
    await expectLater(
      backend.restartOwnedEngine(),
      throwsA(isA<BackendException>()),
    );
    expect(runner.daemons.single.isRunning, isTrue);
    expect(
      runner.commands.where((args) => args.contains('desktop.quit')),
      isEmpty,
    );
  });

  test(
    'tracks and cancels a real job without replaying its submission',
    () async {
      final runner = FakeLauncher();
      var canceled = false;
      runner.onCommand = (arguments) {
        if (arguments.length > 1 &&
            const {'call', 'job', 'cancel'}.contains(arguments[1])) {
          if (arguments[1] == 'cancel') canceled = true;
          return FakeProcess.json(
            envelope({
              'job': {
                'id': 'long-job',
                'operation': 'provider.load',
                'state': canceled ? 'canceled' : 'running',
                if (canceled)
                  'error': {'code': 'canceled', 'message': 'job canceled'},
              },
            }),
          );
        }
        return null;
      };
      final backend = runner.backend();
      addTearDown(backend.close);
      final snapshots = <List<BackendJob>>[];
      final subscription = backend.jobs.listen(snapshots.add);
      addTearDown(subscription.cancel);
      final outcome = expectLater(
        backend.call('provider.load', {
          'provider': 'local',
          'playlist': 'private-playlist-value',
        }),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            'canceled',
          ),
        ),
      );
      await eventually(() => backend.currentJobs.isNotEmpty);
      expect(backend.currentJobs.single.operation, 'provider.load');
      await backend.cancelJob('long-job');
      await outcome;
      expect(backend.currentJobs.single.state, 'canceled');
      expect(
        snapshots.any((jobs) => jobs.single.cancellationRequested),
        isTrue,
      );
      expect(
        runner.commands.where((args) => args.contains('call')),
        hasLength(1),
      );
      expect(runner.commands.where((args) => args.contains('cancel')).single, [
        'remote',
        'cancel',
        'long-job',
      ]);
    },
  );

  test('honors a legacy provider that cannot cancel browser sign-in', () async {
    final runner = FakeLauncher();
    var finished = false;
    runner.onCommand = (arguments) {
      if (arguments.length > 1 &&
          const {'call', 'job'}.contains(arguments[1])) {
        return FakeProcess.json(
          envelope({
            'job': {
              'id': 'legacy-auth',
              'operation': 'provider.auth',
              'state': finished ? 'succeeded' : 'running',
              if (finished) 'result': {'ok': true},
            },
          }),
        );
      }
      return null;
    };
    final backend = runner.backend();
    addTearDown(backend.close);
    final outcome = backend.call('provider.auth', {'provider': 'legacy'});
    await eventually(
      () => backend.currentJobs.isNotEmpty && runner.eventProcesses.isNotEmpty,
    );
    runner.eventProcesses.single.line({
      'event': 'provider.auth',
      'data': {
        'ok': true,
        'auth': {
          'provider': 'legacy',
          'state': 'authenticating',
          'cancellable': false,
        },
      },
    });
    await eventually(() => !backend.currentJobs.single.cancellable);
    await expectLater(
      backend.cancelJob('legacy-auth'),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
    expect(runner.commands.where((args) => args.contains('cancel')), isEmpty);
    finished = true;
    await outcome;
  });

  test(
    'delivers reviewed plugin proof and preference values through stdin',
    () async {
      final runner = FakeLauncher();
      final payloads = <Map<String, dynamic>>[];
      runner.onCommand = (arguments) {
        if (arguments.contains('schema')) {
          return FakeProcess.json({'ok': true, 'fields': [], 'values': {}});
        }
        return FakeInputProcess((process, input) {
          payloads.add(jsonDecode(input) as Map<String, dynamic>);
          process.finish(output: jsonEncode({'ok': true}));
        });
      };
      final backend = runner.backend();
      addTearDown(backend.close);
      await backend.preferencesSchema();
      await backend.savePreferences({'cache_size': '256'});
      final proof = {
        'token': 'review-token',
        'sha256': 'exact-hash',
        'source': 'https://example.test/plugin.lua',
        'permissions': ['network'],
      };
      await backend.pluginAction('apply', proof);
      await backend.pluginAction('configure', {
        'name': 'plugin',
        'values': {'api_key': 'private-key'},
      });
      expect(payloads, [
        {'cache_size': '256'},
        proof,
        {
          'name': 'plugin',
          'values': {'api_key': 'private-key'},
        },
      ]);
      expect(runner.commands, [
        ['preferences', 'schema'],
        ['preferences', 'apply'],
        ['plugins', 'desktop', 'apply'],
        ['plugins', 'desktop', 'configure'],
      ]);
      expect(runner.commands.expand((args) => args), isNot(contains('--yes')));
      expect(runner.daemons, isEmpty);
    },
  );

  testWidgets('job panel displays lifecycle and sends actual cancellation', (
    tester,
  ) async {
    final backend = WidgetJobsBackend();
    addTearDown(backend.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: JobsPanel(backend: backend)),
      ),
    );
    expect(find.text('Provider sign-in'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel operation'));
    await tester.pump();
    expect(backend.canceled, ['visible-job']);
    expect(find.textContaining('Canceled'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'provider sign-in cancels its own job and clears the sign-in URL',
    (tester) async {
      final backend = SignInBackend();
      addTearDown(backend.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderSignIn(
            backend: backend,
            provider: 'remote',
            name: 'Remote',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Cancel sign-in'), findsOneWidget);
      await tester.tap(find.text('Cancel sign-in'));
      await tester.pump();
      expect(backend.canceled, ['auth-dialog-job']);
      expect(find.textContaining('Sign-in was canceled.'), findsOneWidget);
      expect(find.text('Open sign-in page'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'legacy provider sign-in does not offer unsupported cancellation',
    (tester) async {
      final backend = SignInBackend(supportsCancellation: false);
      addTearDown(backend.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderSignIn(
            backend: backend,
            provider: 'remote',
            name: 'Remote',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Cancel sign-in'), findsNothing);
      expect(
        find.text(
          'Closing this dialog leaves the provider sign-in attempt running.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      backend.authResult.complete({'ok': true});
      await tester.pump();
    },
  );

  test('reads visualizer frames without creating progress jobs', () async {
    final runner = FakeLauncher();
    runner.onCommand = (arguments) {
      if (arguments.length > 1 && arguments[1] == 'frame') {
        return FakeProcess.json(
          envelope({
            'result': {
              'ok': true,
              'frame': '\u001b[31m▁▃█',
              'width': 100,
              'height': 30,
            },
          }),
        );
      }
      return null;
    };
    final backend = runner.backend();
    addTearDown(backend.close);
    final frame = await backend.readFrame(100, 30);
    expect(frame['frame'], '\u001b[31m▁▃█');
    expect(runner.commands.singleWhere((args) => args.contains('frame')), [
      'remote',
      'frame',
      '--width',
      '100',
      '--height',
      '30',
    ]);
    expect(backend.currentJobs, isEmpty);
  });

  test('refuses to restart a player owned by another application', () async {
    final runner = FakeLauncher();
    final backend = runner.backend();
    addTearDown(backend.close);
    await backend.connect();
    expect(backend.ownsDaemon, isFalse);
    await expectLater(
      backend.restartOwnedEngine(),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'not_owned',
        ),
      ),
    );
    expect(
      runner.commands.where((args) => args.contains('desktop.quit')),
      isEmpty,
    );
    expect(runner.daemons, isEmpty);
  });
}
