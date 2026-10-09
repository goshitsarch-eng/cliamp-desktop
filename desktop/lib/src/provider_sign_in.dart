import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend.dart';

class ProviderSignIn extends StatefulWidget {
  const ProviderSignIn({
    super.key,
    required this.backend,
    required this.provider,
    required this.name,
  });
  final PlayerBackend backend;
  final String provider;
  final String name;
  @override
  State<ProviderSignIn> createState() => _ProviderSignInState();
}

class _ProviderSignInState extends State<ProviderSignIn> {
  Timer? _timer;
  bool _polling = false;
  String _state = 'authenticating';
  String _url = '';
  String? _error;
  bool _cancellable = false;
  bool _cancelRequested = false;
  BackendJob? _job;
  Set<String> _previousJobs = {};
  StreamSubscription<List<BackendJob>>? _jobsSubscription;

  @override
  void initState() {
    super.initState();
    final backend = widget.backend;
    if (backend is JobProgressBackend) {
      _jobsSubscription = (backend as JobProgressBackend).jobs.listen((jobs) {
        for (final job in jobs) {
          if (job.operation == 'provider.auth' &&
              job.provider == widget.provider &&
              !_previousJobs.contains(job.id)) {
            if (mounted) setState(() => _job = job);
            break;
          }
        }
      });
    }
    _signIn();
  }

  Future<void> _signIn() async {
    setState(() {
      _state = 'authenticating';
      _error = null;
      _url = '';
      _cancelRequested = false;
      _cancellable = false;
      _job = null;
    });
    final backend = widget.backend;
    _previousJobs = backend is JobProgressBackend
        ? (backend as JobProgressBackend).currentJobs
              .map((job) => job.id)
              .toSet()
        : {};
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _status());
    unawaited(_status());
    try {
      final result = await widget.backend.call('provider.auth', {
        'provider': widget.provider,
      });
      if (result['ok'] == false) throw StateError('${result['error']}');
      if (mounted) setState(() => _state = 'authenticated');
      _timer?.cancel();
    } catch (error) {
      if (error is BackendException && error.code == 'canceled') {
        if (mounted) {
          setState(() {
            _state = 'canceling';
            _cancelRequested = true;
            _url = '';
          });
        }
        await _status();
        return;
      }
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _state = 'failed';
          _error = error is BackendException && error.code == 'conflict'
              ? 'A sign-in flow is already running for this provider.'
              : 'Check the provider configuration and try again.';
        });
      }
    }
  }

  Future<void> _status() async {
    if (_polling) return;
    _polling = true;
    try {
      final result = await widget.backend.call('provider.auth.status', {
        'provider': widget.provider,
      });
      final auth = result['auth'];
      if (mounted && auth is Map) {
        setState(() {
          final next = '${auth['state'] ?? _state}';
          if (next != 'idle' || _state != 'authenticating') {
            _state = _cancelRequested && next == 'authenticating'
                ? 'canceling'
                : next;
          }
          _cancellable = auth['cancellable'] == true;
          _url = _state == 'authenticating' ? '${auth['url'] ?? ''}' : '';
          if (_state == 'failed') {
            _error = 'The provider could not complete sign-in.';
          }
          if (_state == 'canceled') _error = null;
        });
        if (const {'authenticated', 'canceled', 'failed'}.contains(_state)) {
          _timer?.cancel();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not read the provider sign-in state.');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancel() async {
    final backend = widget.backend;
    final job = _job;
    if (backend is! JobProgressBackend ||
        job == null ||
        !job.cancellable ||
        !_cancellable) {
      return;
    }
    setState(() {
      _cancelRequested = true;
      _state = 'canceling';
      _url = '';
      _error = null;
    });
    try {
      await (backend as JobProgressBackend).cancelJob(job.id);
      await _status();
    } catch (_) {
      if (mounted) {
        setState(() {
          _cancelRequested = false;
          _state = 'authenticating';
          _error =
              'Sign-in could not be canceled. Check its current state before trying again.';
        });
      }
    }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(_url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(
        () => _error = 'This provider did not return a valid HTTP sign-in URL.',
      );
      return;
    }
    try {
      final executable = Platform.isMacOS
          ? 'open'
          : Platform.isWindows
          ? 'rundll32.exe'
          : 'xdg-open';
      final arguments = Platform.isWindows
          ? ['url.dll,FileProtocolHandler', uri.toString()]
          : [uri.toString()];
      final result = await Process.run(
        executable,
        arguments,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw const FileSystemException(
          'Unable to open the browser. Copy the link and open it manually.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_jobsSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Connect ${widget.name}'),
    content: SizedBox(
      width: 470,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_state == 'authenticating' ||
              _state == 'idle' ||
              _state == 'canceling')
            const LinearProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            _state == 'authenticated'
                ? 'You’re connected. Your account is ready to browse.'
                : _state == 'failed'
                ? 'Sign-in could not be completed.'
                : _state == 'canceled'
                ? 'Sign-in was canceled. You can try again when you’re ready.'
                : _state == 'canceling'
                ? 'Canceling the provider sign-in…'
                : _url.isEmpty
                ? 'Waiting for the provider’s sign-in instructions…'
                : 'Open the sign-in page, complete the steps in your browser, then return here.',
          ),
          if (_url.isNotEmpty && _state == 'authenticating') ...[
            const SizedBox(height: 18),
            SelectableText(_url, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _openBrowser,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open sign-in page'),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Copy sign-in link',
                  onPressed: () => Clipboard.setData(ClipboardData(text: _url)),
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          if (_state == 'authenticating') ...[
            const SizedBox(height: 16),
            const Text(
              'Closing this dialog leaves the provider sign-in attempt running.',
              style: TextStyle(fontSize: 11, color: Color(0xff9da4b6)),
            ),
          ],
        ],
      ),
    ),
    actions: [
      if (_state == 'authenticating' &&
          _cancellable &&
          _job?.cancellable == true)
        TextButton(onPressed: _cancel, child: const Text('Cancel sign-in')),
      if (_state == 'failed' || _state == 'canceled')
        TextButton(onPressed: _signIn, child: const Text('Try again')),
      TextButton(
        onPressed: () => Navigator.pop(context, _state == 'authenticated'),
        child: Text(_state == 'authenticated' ? 'Done' : 'Close'),
      ),
    ],
  );
}
