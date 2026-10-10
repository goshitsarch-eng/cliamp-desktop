import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The desktop UI's boundary to the unchanged cliamp audio engine.
abstract class PlayerBackend {
  Future<void> connect();
  Future<Map<String, dynamic>> snapshot();
  Future<Map<String, dynamic>> capabilities();
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]);

  /// Go IPC envelopes with `event` and `data` keys. Errors signal a lost
  /// connection; a fresh runtime.state event follows a successful reconnect.
  Stream<Map<String, dynamic>> get events;
  Stream<List<double>> get spectrum;
  Future<void> close();
}

/// Optional provider configuration support, independent of audio connectivity.
abstract class ProviderSetupBackend {
  Future<Map<String, dynamic>> setupSchema(
    String provider, [
    Map<String, String> values = const {},
  ]);
  Future<Map<String, dynamic>> saveProvider(
    String provider,
    Map<String, String> values, {
    bool verifyConnection = true,
  });
  bool get ownsDaemon;
  Future<void> restartOwnedEngine();
}

abstract class DesktopManagementBackend {
  Future<Map<String, dynamic>> preferencesSchema();
  Future<Map<String, dynamic>> savePreferences(Map<String, String> values);
  Future<Map<String, dynamic>> pluginAction(
    String action, [
    Map<String, dynamic> values = const {},
  ]);
  bool get ownsDaemon;
  Future<void> restartOwnedEngine();
}

/// Progress contains operation names and lifecycle data only: never parameters,
/// provider credentials, OAuth links, plugin source, or operation result data.
class BackendJob {
  const BackendJob({
    required this.id,
    required this.operation,
    required this.state,
    required this.createdAt,
    this.finishedAt,
    this.cancellable = true,
    this.cancellationRequested = false,
    this.provider,
  });
  final String id;
  final String operation;
  final String state;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final bool cancellable;
  final bool cancellationRequested;
  final String? provider;
  bool get isActive => state == 'queued' || state == 'running';

  BackendJob copyWith({
    String? state,
    bool? cancellable,
    bool? cancellationRequested,
  }) => BackendJob(
    id: id,
    operation: operation,
    state: state ?? this.state,
    createdAt: createdAt,
    finishedAt:
        finishedAt ??
        (state != null && state != 'queued' && state != 'running'
            ? DateTime.now()
            : null),
    cancellable: cancellable ?? this.cancellable,
    cancellationRequested: cancellationRequested ?? this.cancellationRequested,
    provider: provider,
  );
}

abstract class JobProgressBackend {
  List<BackendJob> get currentJobs;
  Stream<List<BackendJob>> get jobs;
  Future<void> cancelJob(String jobId);
}

abstract class VisualizerFrameBackend {
  Future<Map<String, dynamic>> readFrame(int width, int height);
}

class BackendException implements Exception {
  const BackendException(this.message, {this.code = 'backend_error'});
  final String message;
  final String code;
  @override
  String toString() => message;
}

/// Small process boundary for deterministic lifecycle and protocol tests.
abstract class BackendProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Optional stdin support keeps existing process fakes source compatible.
abstract class InputBackendProcess implements BackendProcess {
  Future<void> writeInput(String input);
}

typedef ProcessLauncher =
    Future<BackendProcess> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    );

class _SystemProcess implements InputBackendProcess {
  _SystemProcess(this.process);
  final Process process;
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

Future<BackendProcess> _launch(
  String executable,
  List<String> arguments,
  Map<String, String> environment,
) async => _SystemProcess(
  await Process.start(
    executable,
    arguments,
    environment: environment,
    runInShell: false,
  ),
);

/// Controls cliamp through its portable CLI V2 client. Attaches to an existing
/// player, or owns a headless child when there is no player to attach to.
/// Commands are passed as argument arrays, so paths and provider input never
/// pass through a shell. Submitted operations are never automatically replayed.
class CliampBackend
    implements
        PlayerBackend,
        ProviderSetupBackend,
        DesktopManagementBackend,
        JobProgressBackend,
        VisualizerFrameBackend {
  CliampBackend({
    String? executable,
    Map<String, String>? environment,
    ProcessLauncher? processLauncher,
    this.commandTimeout = const Duration(seconds: 15),
    this.operationTimeout = const Duration(minutes: 5),
    this.startupTimeout = const Duration(seconds: 15),
    this.shutdownTimeout = const Duration(seconds: 3),
    this.refreshInterval = const Duration(seconds: 1),
    this.reconnectDelay = const Duration(seconds: 1),
  }) : _executable = executable,
       _environment = Map.unmodifiable(environment ?? const {}),
       _launcher = processLauncher ?? _launch;

  String? _executable;
  final Map<String, String> _environment;
  final ProcessLauncher _launcher;
  final Duration commandTimeout;
  final Duration operationTimeout;
  final Duration startupTimeout;
  final Duration shutdownTimeout;
  final Duration refreshInterval;
  final Duration reconnectDelay;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _spectrum = StreamController<List<double>>.broadcast();
  final _jobUpdates = StreamController<List<BackendJob>>.broadcast();
  final Map<String, BackendJob> _jobs = {};
  final Map<String, DateTime> _jobUpdated = {};
  final Map<String, String> _jobProviders = {};
  final Map<String, bool> _authCancellable = {};
  final Set<String> _canceling = {};
  final Set<BackendProcess> _children = {};
  BackendProcess? _daemon;
  BackendProcess? _eventProcess;
  BackendProcess? _spectrumProcess;
  String _daemonLog = '';
  int? _daemonExit;
  int _generation = 0;
  bool _closed = false;
  bool _connected = false;
  bool _refreshing = false;
  Future<void>? _connecting;
  Future<void>? _closing;
  Future<void>? _restarting;
  Future<void>? _stopping;
  Timer? _refreshTimer;
  Timer? _reconnectTimer;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Stream<List<double>> get spectrum => _spectrum.stream;
  @override
  Stream<List<BackendJob>> get jobs => _jobUpdates.stream;
  @override
  List<BackendJob> get currentJobs {
    final values = _jobs.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return List.unmodifiable(values);
  }

  void _checkOpen() {
    if (_closed) {
      throw const BackendException(
        'The player connection is closed.',
        code: 'closed',
      );
    }
  }

  Future<String> _resolveExecutable() async {
    if (_executable != null && _executable!.isNotEmpty) return _executable!;
    final configured =
        _environment['CLIAMP_BINARY'] ?? Platform.environment['CLIAMP_BINARY'];
    if (configured != null && configured.isNotEmpty) {
      return _executable = configured;
    }
    final name = Platform.isWindows ? 'cliamp.exe' : 'cliamp';
    final directory = File(Platform.resolvedExecutable).parent;
    final adjacent = File('${directory.path}${Platform.pathSeparator}$name');
    if (await adjacent.exists()) return _executable = adjacent.path;
    if (Platform.isMacOS) {
      final resource = File('${directory.parent.path}/Resources/$name');
      if (await resource.exists()) return _executable = resource.path;
    }
    return _executable = name;
  }

  Future<BackendProcess> _start(
    List<String> arguments, {
    bool allowClosed = false,
  }) async {
    if (!allowClosed) _checkOpen();
    final executable = await _resolveExecutable();
    if (!allowClosed) _checkOpen();
    try {
      final child = await _launcher(executable, arguments, _environment);
      if (_closed && !allowClosed) {
        child.kill();
        throw const BackendException(
          'The player connection is closed.',
          code: 'closed',
        );
      }
      _children.add(child);
      unawaited(child.exitCode.then((_) => _children.remove(child)));
      return child;
    } on ProcessException catch (error) {
      throw BackendException(
        'Could not start cliamp ($executable). Build the desktop bundle or '
        'set CLIAMP_BINARY to your cliamp executable. ${error.message}',
        code: 'executable_unavailable',
      );
    }
  }

  @override
  Future<void> connect() async {
    _checkOpen();
    if (_restarting != null) return _restarting;
    if (_connected) return;
    if (_connecting != null) return _connecting;
    final pending = _connect();
    _connecting = pending;
    try {
      await pending;
    } finally {
      if (identical(_connecting, pending)) _connecting = null;
    }
  }

  Future<void> _connect() async {
    Map<String, dynamic>? current;
    try {
      current = await _readSnapshot();
    } on BackendException catch (error) {
      // Permission, configuration and protocol errors must not launch a second
      // instance or hide the actionable error from the user.
      if (error.code != 'not_running') rethrow;
    }
    if (current == null) {
      if (_daemon == null || _daemonExit != null) {
        for (final job in _jobs.values.toList()) {
          if (job.isActive) {
            _jobs[job.id] = job.copyWith(
              state: 'interrupted',
              cancellable: false,
            );
          }
        }
        _publishJobs();
        _daemonLog = '';
        _daemonExit = null;
        final daemon = await _start(['--daemon']);
        _daemon = daemon;
        void capture(List<int> bytes) {
          _daemonLog += utf8.decode(bytes, allowMalformed: true);
          if (_daemonLog.length > 4096) {
            _daemonLog = _daemonLog.substring(_daemonLog.length - 4096);
          }
        }

        daemon.stdout.listen(capture);
        daemon.stderr.listen(capture);
        unawaited(
          daemon.exitCode.then((code) {
            if (identical(_daemon, daemon)) _daemonExit = code;
          }),
        );
      }
      final deadline = DateTime.now().add(startupTimeout);
      while (current == null) {
        _checkOpen();
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          _daemon?.kill();
          throw BackendException(
            'cliamp did not become ready within '
            '${startupTimeout.inSeconds} seconds. ${_daemonLog.trim()}',
            code: 'startup_timeout',
          );
        }
        try {
          current = await _readSnapshot(timeout: remaining);
        } on BackendException catch (error) {
          if (error.code != 'not_running') rethrow;
          if (_daemonExit != null) {
            throw BackendException(
              'cliamp exited before it was ready (exit $_daemonExit). '
              '${_daemonLog.trim()}',
              code: 'startup_failed',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    _checkOpen();
    _connected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _publishSnapshot(current);
    _startStreams();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (_) => _refresh());
  }

  void _publishSnapshot(Map<String, dynamic> value) {
    if (!_closed) _events.add({'event': 'runtime.state', 'data': value});
  }

  Future<void> _refresh() async {
    if (_closed || !_connected || _refreshing) return;
    _refreshing = true;
    try {
      _publishSnapshot(await _readSnapshot());
      for (final job in currentJobs.where((job) => job.isActive)) {
        if (_closed || !_connected) break;
        if (DateTime.now().difference(_jobUpdated[job.id] ?? job.createdAt) <
            const Duration(seconds: 2)) {
          continue;
        }
        try {
          final response = await _command(['remote', 'job', job.id]);
          if (response['job'] is Map<String, dynamic>) {
            _recordJob(response['job'] as Map<String, dynamic>);
          }
        } on BackendException catch (error) {
          if (error.code != 'not_found') rethrow;
          _jobs[job.id] = job.copyWith(
            state: 'interrupted',
            cancellable: false,
          );
          _publishJobs();
        }
      }
    } catch (error) {
      _scheduleReconnect(error);
    } finally {
      _refreshing = false;
    }
  }

  void _stopStreams() {
    _generation++;
    _eventProcess?.kill();
    _spectrumProcess?.kill();
    _eventProcess = null;
    _spectrumProcess = null;
    _refreshTimer?.cancel();
  }

  void _startStreams() {
    _stopStreams();
    final generation = _generation;
    unawaited(_watchStream(false, generation));
    unawaited(_watchStream(true, generation));
  }

  Future<void> _watchStream(bool bands, int generation) async {
    BackendProcess? process;
    try {
      process = await _start(
        bands
            ? ['visstream', '--fps', '30']
            : [
                'remote',
                'events',
                'runtime.state',
                'runtime.playback',
                'runtime.playlist',
                'runtime.settings',
                'runtime.job',
                'provider.auth',
              ],
      );
      if (_closed || generation != _generation) {
        process.kill();
        return;
      }
      if (bands) {
        _spectrumProcess = process;
      } else {
        _eventProcess = process;
      }
      var diagnostic = '';
      process.stderr.listen((bytes) {
        diagnostic += utf8.decode(bytes, allowMalformed: true);
        if (diagnostic.length > 4096) {
          diagnostic = diagnostic.substring(diagnostic.length - 4096);
        }
      });
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (_closed || generation != _generation) break;
        if (line.trim().isEmpty) continue;
        final envelope = _decodeObject(line);
        if (bands) {
          final values = envelope['bands'];
          if (values is List && values.every((value) => value is num)) {
            _spectrum.add(
              values.map((value) => (value as num).toDouble()).toList(),
            );
          }
        } else {
          if (envelope['event'] == 'system.overflow') {
            throw const BackendException(
              'The player event stream overflowed; refreshing state.',
              code: 'resync_required',
            );
          }
          if (envelope['event'] == 'runtime.job') {
            final data = envelope['data'];
            if (data is Map<String, dynamic>) {
              final job = data['job'] ?? data;
              if (job is Map<String, dynamic> && _jobs.containsKey(job['id'])) {
                _recordJob(job);
              }
            }
          } else if (envelope['event'] == 'provider.auth') {
            final data = envelope['data'];
            if (data is Map<String, dynamic> && data['auth'] is Map) {
              final auth = data['auth'] as Map;
              final provider = auth['provider'];
              if (provider is String && auth['cancellable'] is bool) {
                _authCancellable[provider] = auth['cancellable'] as bool;
                for (final job in _jobs.values.toList()) {
                  if (job.isActive && _jobProviders[job.id] == provider) {
                    _jobs[job.id] = job.copyWith(
                      cancellable: auth['cancellable'] as bool,
                    );
                  }
                }
                _publishJobs();
              }
            }
          }
          _events.add(envelope);
        }
      }
      if (!_closed && generation == _generation) {
        throw BackendException(
          'The player ${bands ? 'spectrum' : 'event'} connection closed. '
          '${diagnostic.trim()}',
          code: 'disconnected',
        );
      }
    } catch (error) {
      if (!_closed && generation == _generation) _scheduleReconnect(error);
    } finally {
      process?.kill();
    }
  }

  void _scheduleReconnect(Object error) {
    if (_closed || _restarting != null || _reconnectTimer != null) return;
    _connected = false;
    _stopStreams();
    _events.addError(error);
    _reconnectTimer = Timer(reconnectDelay, () async {
      _reconnectTimer = null;
      if (_closed) return;
      try {
        // connect reads authoritative state before it opens new subscriptions.
        await connect();
      } catch (error) {
        _scheduleReconnect(error);
      }
    });
  }

  Future<Map<String, dynamic>> _command(
    List<String> arguments, {
    Duration? timeout,
    bool allowClosed = false,
    String? input,
    bool requireV2 = true,
    bool privateErrors = false,
  }) async {
    final child = await _start(arguments, allowClosed: allowClosed);
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    try {
      final results = await Future.wait<Object>([
        child.exitCode,
        output,
        errors,
        if (input != null) _writeInput(child, input),
      ]).timeout(timeout ?? commandTimeout);
      final status = results[0] as int;
      final stdout = (results[1] as String).trim();
      final stderr = (results[2] as String).trim();
      if (status != 0) {
        if (privateErrors) throw _setupError();
        final detail = stderr.isNotEmpty ? stderr : stdout;
        final notRunning =
            detail.contains('cliamp is not running') ||
            detail.contains('no socket at');
        final protocolCode = RegExp(
          r'\((invalid_version|invalid_request|invalid_params|unknown_operation|not_found|conflict|unavailable|canceled|internal_error)\)',
        ).firstMatch(detail)?.group(1);
        throw BackendException(
          detail.isEmpty ? 'cliamp exited with status $status.' : detail,
          code: notRunning ? 'not_running' : protocolCode ?? 'command_failed',
        );
      }
      final response = _decodeObject(stdout);
      if (requireV2 && response['version'] != 2) {
        throw const BackendException(
          'cliamp returned an unsupported IPC version.',
          code: 'invalid_version',
        );
      }
      if (response['ok'] != true) {
        if (privateErrors) throw _setupError();
        _throwProtocolError(response['error']);
      }
      return response;
    } on TimeoutException {
      child.kill();
      if (privateErrors) {
        throw const BackendException(
          'Provider setup timed out. Check the saved provider settings before trying again.',
          code: 'timeout',
        );
      }
      throw const BackendException(
        'The cliamp command timed out. An accepted operation may still finish '
        'in the player; refresh its state before trying again.',
        code: 'timeout',
      );
    } finally {
      // Also closes a client whose output could not be decoded.
      child.kill();
    }
  }

  Future<Object> _writeInput(BackendProcess process, String input) async {
    if (process is! InputBackendProcess) {
      throw const BackendException(
        'This process launcher does not support provider setup.',
        code: 'stdin_unavailable',
      );
    }
    await process.writeInput(input);
    return true;
  }

  BackendException _setupError() => const BackendException(
    'Provider setup could not complete. Check the required fields and try again.',
    code: 'setup_failed',
  );

  Future<Map<String, dynamic>> _setupRequest(
    String command,
    String provider,
    Map<String, String> values, {
    bool verifyConnection = true,
  }) async {
    try {
      return await _command(
        [
          'setup',
          command,
          if (provider.isNotEmpty) ...['--provider', provider],
          if (command == 'apply' && !verifyConnection) '--save-without-check',
        ],
        input: '${jsonEncode(values)}\n',
        timeout: command == 'apply' ? operationTimeout : commandTimeout,
        requireV2: false,
        privateErrors: true,
      );
    } on BackendException {
      rethrow;
    } catch (_) {
      // Provider probes and process pipe failures may include request values.
      // Keep credential-bearing diagnostics out of the interface and logs.
      throw _setupError();
    }
  }

  @override
  Future<Map<String, dynamic>> setupSchema(
    String provider, [
    Map<String, String> values = const {},
  ]) => _setupRequest('schema', provider, values);

  @override
  Future<Map<String, dynamic>> saveProvider(
    String provider,
    Map<String, String> values, {
    bool verifyConnection = true,
  }) => _setupRequest(
    'apply',
    provider,
    values,
    verifyConnection: verifyConnection,
  );

  Future<Map<String, dynamic>> _managementRequest(
    List<String> arguments, {
    Map<String, dynamic>? values,
    bool slow = false,
  }) async {
    try {
      return await _command(
        arguments,
        input: values == null ? null : '${jsonEncode(values)}\n',
        timeout: slow ? operationTimeout : commandTimeout,
        requireV2: false,
        privateErrors: true,
      );
    } on BackendException catch (error) {
      if (error.code == 'closed' || error.code == 'executable_unavailable') {
        rethrow;
      }
      throw const BackendException(
        'The settings or plugin operation could not complete. Check the requested changes and try again.',
        code: 'management_failed',
      );
    } catch (_) {
      throw const BackendException(
        'The settings or plugin operation could not complete.',
        code: 'management_failed',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> preferencesSchema() =>
      _managementRequest(['preferences', 'schema']);

  @override
  Future<Map<String, dynamic>> savePreferences(
    Map<String, String> values,
  ) async {
    final result = await _managementRequest([
      'preferences',
      'apply',
    ], values: values);
    // An attached terminal saves its current theme on exit. Apply a changed
    // theme to that shared renderer so its exit cannot overwrite this edit.
    if (values.containsKey('theme')) {
      try {
        await call('desktop.theme', {'name': values['theme']});
      } catch (_) {
        throw const BackendException(
          'Preferences were saved, but the running player could not apply the theme. '
          'Keep the player open and retry, or restart it and reapply the theme.',
          code: 'theme_sync_failed',
        );
      }
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> pluginAction(
    String action, [
    Map<String, dynamic> values = const {},
  ]) {
    if (!const {
      'list',
      'prepare',
      'review',
      'apply',
      'trust',
      'remove',
      'configure',
    }.contains(action)) {
      throw const BackendException(
        'Unknown plugin management action.',
        code: 'invalid_request',
      );
    }
    return _managementRequest(
      ['plugins', 'desktop', action],
      values: values,
      slow: action == 'prepare',
    );
  }

  void _publishJobs() {
    if (!_closed) _jobUpdates.add(currentJobs);
  }

  void _recordJob(
    Map<String, dynamic> raw, {
    String? operation,
    String? provider,
  }) {
    final id = raw['id'];
    if (id is! String) return;
    final previous = _jobs[id];
    final name =
        operation ??
        raw['operation']?.toString() ??
        previous?.operation ??
        'operation';
    // These are continuous UI reads, not user-started background work.
    if (name == 'desktop.vis.frame' || name == 'provider.auth.status') return;
    final state = raw['state']?.toString() ?? 'running';
    if (previous != null &&
        !previous.isActive &&
        (state == 'queued' || state == 'running')) {
      return;
    }
    if (provider != null) _jobProviders[id] = provider;
    _jobUpdated[id] = DateTime.now();
    final active = state == 'queued' || state == 'running';
    if (!active) _canceling.remove(id);
    _jobs[id] = BackendJob(
      id: id,
      operation: RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name)
          ? name
          : 'operation',
      state: state,
      createdAt:
          DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
          previous?.createdAt ??
          DateTime.now(),
      finishedAt:
          DateTime.tryParse(raw['finished_at']?.toString() ?? '') ??
          (active ? null : DateTime.now()),
      cancellable: active && (_authCancellable[_jobProviders[id]] ?? true),
      cancellationRequested: _canceling.contains(id),
      provider: _jobProviders[id],
    );
    final completed = currentJobs
        .where((job) => !job.isActive)
        .skip(30)
        .toList();
    for (final old in completed) {
      _jobs.remove(old.id);
      _jobUpdated.remove(old.id);
      _jobProviders.remove(old.id);
    }
    _publishJobs();
  }

  @override
  Future<void> cancelJob(String jobId) async {
    _checkOpen();
    final job = _jobs[jobId];
    if (job == null || !job.isActive) return;
    if (!job.cancellable) {
      throw const BackendException(
        'This provider cannot stop its sign-in flow. Finish or close the provider sign-in window.',
        code: 'unavailable',
      );
    }
    if (!_canceling.add(jobId)) return;
    _jobs[jobId] = job.copyWith(cancellationRequested: true);
    _publishJobs();
    try {
      await connect();
      final response = await _command(['remote', 'cancel', jobId]);
      final updated = response['job'];
      if (updated is Map<String, dynamic>) _recordJob(updated);
    } finally {
      _canceling.remove(jobId);
      final current = _jobs[jobId];
      if (current != null) {
        _jobs[jobId] = current.copyWith(cancellationRequested: false);
      }
      _publishJobs();
    }
  }

  @override
  bool get ownsDaemon =>
      !_closed &&
      _daemon != null &&
      _daemonExit == null &&
      _children.contains(_daemon);

  @override
  Future<void> restartOwnedEngine() async {
    _checkOpen();
    if (_restarting != null) return _restarting;
    if (!ownsDaemon) {
      throw const BackendException(
        'This player was started elsewhere. Restart it there to load the new provider settings.',
        code: 'not_owned',
      );
    }
    final pending = _restartOwnedEngine();
    _restarting = pending;
    try {
      await pending;
    } finally {
      if (identical(_restarting, pending)) _restarting = null;
    }
  }

  Future<List<Map<String, dynamic>>> _sessionTracks(String operation) async {
    final tracks = <Map<String, dynamic>>[];
    while (true) {
      final page = await _callConnected(operation, {
        'offset': tracks.length,
        'limit': 200,
      });
      final rows = (page['tracks'] as List? ?? []).whereType<Map>();
      tracks.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
      if (tracks.length >=
          ((page['total'] as num?)?.toInt() ?? tracks.length)) {
        return tracks;
      }
      if (rows.isEmpty) {
        throw const BackendException(
          'Unable to capture the complete queue before restarting.',
          code: 'incomplete_queue',
        );
      }
    }
  }

  Future<void> _restartOwnedEngine() async {
    // Capture before stopping: a failed read must leave the original player intact.
    var state = await _readSnapshot();
    final tracks = await _sessionTracks('queue.list');
    final next = await _sessionTracks('playnext.list');
    final captured = await _readSnapshot();
    if (captured['playlist_revision'] != state['playlist_revision']) {
      throw const BackendException(
        'The queue changed while preparing to restart. Try again.',
        code: 'queue_changed',
      );
    }
    state = captured;
    _connected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopStreams();
    await _stopOwnedDaemon();
    _checkOpen();
    await _connect();
    await _callConnected('queue.clear');
    for (var offset = 0; offset < tracks.length; offset += 200) {
      await _callConnected('tracks.append', {
        'tracks': tracks.skip(offset).take(200).toList(),
        'play': false,
      });
    }
    if (state['shuffle'] is bool) {
      await _callConnected('shuffle', {
        'name': state['shuffle'] == true ? 'on' : 'off',
      });
    }
    if (state['repeat'] is String) {
      await _callConnected('repeat', {
        'name': (state['repeat'] as String).toLowerCase(),
      });
    }
    final index = (state['index'] as num?)?.toInt() ?? 0;
    if (tracks.isNotEmpty &&
        index >= 0 &&
        index < tracks.length &&
        (state['state'] == 'playing' || state['state'] == 'paused')) {
      await _callConnected('queue.play', {'index': index});
      final deadline = DateTime.now().add(operationTimeout);
      while (true) {
        final current = await _readSnapshot();
        if ((current['state'] == 'playing' || current['state'] == 'paused') &&
            (current['track'] as Map?)?['path'] == tracks[index]['path']) {
          break;
        }
        if (current['stream_error'] != null ||
            DateTime.now().isAfter(deadline)) {
          throw const BackendException(
            'The queue was restored, but playback could not resume.',
            code: 'resume_failed',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (state['state'] == 'paused') await _callConnected('pause');
      if (state['seekable'] == true && (state['position'] as num? ?? 0) > 0) {
        await _callConnected('seek.absolute', {'value': state['position']});
      }
    }
    for (final entry in next) {
      await _callConnected('queue.enqueue', {'index': entry['index'] ?? 0});
    }
    _publishSnapshot(await _readSnapshot());
  }

  Map<String, dynamic> _decodeObject(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Give the user a stable error without echoing arbitrary provider output.
    }
    throw const BackendException(
      'cliamp returned malformed JSON.',
      code: 'invalid_response',
    );
  }

  Never _throwProtocolError(
    dynamic error, {
    String fallback = 'Operation failed.',
  }) {
    if (error is Map) {
      final detail = error['detail'];
      throw BackendException(
        '${error['message'] ?? fallback}'
        '${detail is String && detail.isNotEmpty ? ': $detail' : ''}',
        code: error['code']?.toString() ?? 'operation_failed',
      );
    }
    throw BackendException(
      error is String ? error : fallback,
      code: 'operation_failed',
    );
  }

  Future<Map<String, dynamic>> _readSnapshot({Duration? timeout}) async {
    final response = await _command(['remote', 'state'], timeout: timeout);
    final state = response['snapshot'];
    if (state is! Map<String, dynamic>) {
      throw const BackendException(
        'cliamp returned no runtime snapshot.',
        code: 'invalid_response',
      );
    }
    return state;
  }

  @override
  Future<Map<String, dynamic>> snapshot() async {
    await connect();
    return _readSnapshot();
  }

  @override
  Future<Map<String, dynamic>> capabilities() async {
    await connect();
    final response = await _command(['remote', 'capabilities']);
    final result = response['result'];
    if (result is List) return {'operations': result};
    if (result is Map<String, dynamic>) return result;
    throw const BackendException(
      'cliamp returned no capabilities.',
      code: 'invalid_response',
    );
  }

  @override
  Future<Map<String, dynamic>> readFrame(int width, int height) async {
    await connect();
    final response = await _command([
      'remote',
      'frame',
      '--width',
      '$width',
      '--height',
      '$height',
    ]);
    final frame = response['result'];
    if (frame is! Map<String, dynamic>) {
      throw const BackendException(
        'cliamp returned no visualizer frame.',
        code: 'invalid_response',
      );
    }
    return frame;
  }

  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    await connect();
    return _callConnected(operation, params);
  }

  Future<Map<String, dynamic>> _callConnected(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    final deadline = DateTime.now().add(operationTimeout);
    var response = await _command([
      'remote',
      'call',
      '--params',
      jsonEncode(params),
      operation,
    ]);
    while (true) {
      final job = response['job'];
      if (job is! Map<String, dynamic> || job['id'] is! String) {
        throw const BackendException(
          'cliamp returned no operation job.',
          code: 'invalid_response',
        );
      }
      final state = job['state'];
      _recordJob(
        job,
        operation: operation,
        provider: operation == 'provider.auth'
            ? params['provider']?.toString()
            : null,
      );
      if (state == 'succeeded' || state == 'failed' || state == 'canceled') {
        final stateSnapshot = job['snapshot'];
        if (stateSnapshot is Map<String, dynamic>) {
          _publishSnapshot(stateSnapshot);
        }
        if (state != 'succeeded') {
          _throwProtocolError(job['error'], fallback: 'Operation $state.');
        }
        final result = job['result'];
        if (result == null) return {};
        if (result is! Map<String, dynamic>) {
          throw const BackendException(
            'cliamp returned an invalid job result.',
            code: 'invalid_response',
          );
        }
        if (result['ok'] == false) _throwProtocolError(result['error']);
        return result;
      }
      if (state != 'queued' && state != 'running') {
        throw const BackendException(
          'cliamp returned an unknown job state.',
          code: 'invalid_response',
        );
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw BackendException(
          '$operation is still running (job ${job['id']}). '
          'Refresh its state before trying again.',
          code: 'timeout',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _checkOpen();
      response = await _command([
        'remote',
        'job',
        job['id'] as String,
      ], timeout: remaining < commandTimeout ? remaining : commandTimeout);
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _stopOwnedDaemon() async {
    if (_stopping != null) return _stopping;
    final daemon = _daemon;
    if (daemon == null) return;
    final pending = _stopDaemonProcess(daemon);
    _stopping = pending;
    try {
      await pending;
      if (identical(_daemon, daemon)) {
        _daemon = null;
        _daemonExit = null;
      }
    } finally {
      if (identical(_stopping, pending)) _stopping = null;
    }
  }

  Future<void> _stopDaemonProcess(BackendProcess daemon) async {
    if (_daemonExit != null || !_children.contains(daemon)) return;
    try {
      // Submit only: polling the quit job races with the socket shutting
      // down. Wait on our own process handle for the normal exit save.
      await _command(
        ['remote', 'call', 'desktop.quit'],
        timeout: shutdownTimeout,
        allowClosed: true,
      );
      await daemon.exitCode.timeout(shutdownTimeout);
      return;
    } catch (_) {
      // Older engines, an unavailable socket, or a stuck shutdown still
      // receive the bounded process termination fallback below.
    }
    daemon.kill();
    try {
      await daemon.exitCode.timeout(shutdownTimeout);
    } on TimeoutException {
      daemon.kill(ProcessSignal.sigkill);
      try {
        await daemon.exitCode.timeout(shutdownTimeout);
      } on TimeoutException {
        throw const BackendException(
          'The owned player could not be stopped. Close it before restarting.',
          code: 'shutdown_failed',
        );
      }
    }
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _connected = false;
    _refreshTimer?.cancel();
    _reconnectTimer?.cancel();
    _stopStreams();
    try {
      await _stopOwnedDaemon();
    } catch (_) {
      // Complete cleanup even when the platform could not stop the daemon.
    }
    // These are only children spawned by this adapter, including its own
    // daemon. An already-running cliamp is never owned or terminated here.
    // IPC shutdown above allows saveOnExit to run on Windows too, where
    // Process.kill otherwise terminates immediately without delivering SIGTERM.
    final children = _children.toList();
    for (final child in children) {
      child.kill();
    }
    await Future.wait(
      children.map((child) async {
        try {
          await child.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          child.kill(ProcessSignal.sigkill);
        }
      }),
    );
    await _events.close();
    await _spectrum.close();
    await _jobUpdates.close();
  }
}
