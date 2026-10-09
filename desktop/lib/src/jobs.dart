import 'dart:async';

import 'package:flutter/material.dart';

import 'backend.dart';

/// Active engine operations, with real V2 job cancellation and elapsed time.
/// Progress is indeterminate because the engine does not report byte percentages.
class JobsPanel extends StatefulWidget {
  const JobsPanel({super.key, required this.backend});
  final JobProgressBackend backend;

  @override
  State<JobsPanel> createState() => _JobsPanelState();
}

class _JobsPanelState extends State<JobsPanel> {
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.backend.currentJobs.any((job) => job.isActive)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cancel(BackendJob job) async {
    setState(() => _error = null);
    try {
      await widget.backend.cancelJob(job.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The operation could not be canceled. Check its current state before trying again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<BackendJob>>(
    stream: widget.backend.jobs,
    initialData: widget.backend.currentJobs,
    builder: (context, snapshot) {
      final jobs = (snapshot.data ?? widget.backend.currentJobs).toList()
        ..sort((left, right) {
          if (left.isActive != right.isActive) return left.isActive ? -1 : 1;
          return right.createdAt.compareTo(left.createdAt);
        });
      final active = jobs.where((job) => job.isActive).length;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.work_history_outlined),
              title: const Text('Background activity'),
              subtitle: Text(
                active == 0 ? 'No operations running' : '$active running',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Provider loading, downloads, and sign-in will appear here.',
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _jobTile(jobs[index]),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _jobTile(BackendJob job) {
    final elapsed = (job.finishedAt ?? DateTime.now()).difference(
      job.createdAt,
    );
    final seconds = elapsed.inSeconds.clamp(0, 999999);
    final time = seconds < 60
        ? '${seconds}s'
        : '${seconds ~/ 60}m ${seconds % 60}s';
    final label = switch (job.state) {
      'queued' => 'Queued',
      'running' => 'Running',
      'succeeded' => 'Completed',
      'canceled' => 'Canceled',
      'failed' => 'Failed',
      _ => 'Interrupted',
    };
    return ListTile(
      leading: Icon(switch (job.state) {
        'succeeded' => Icons.check_circle_outline,
        'canceled' => Icons.cancel_outlined,
        'failed' => Icons.error_outline,
        _ => Icons.hourglass_top,
      }),
      title: Text(_operationLabel(job.operation)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${job.cancellationRequested ? 'Canceling' : label} · $time'),
          if (job.isActive)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(),
            ),
          if (job.isActive && !job.cancellable)
            const Text('This provider cannot cancel its sign-in flow.'),
        ],
      ),
      trailing: job.isActive
          ? IconButton(
              tooltip: 'Cancel operation',
              onPressed: job.cancellable && !job.cancellationRequested
                  ? () => _cancel(job)
                  : null,
              icon: const Icon(Icons.close),
            )
          : null,
    );
  }

  String _operationLabel(String operation) => switch (operation) {
    'provider.auth' => 'Provider sign-in',
    'provider.load' => 'Load provider playlist',
    'provider.load_album' => 'Load provider album',
    'provider.search' => 'Search provider',
    'save' => 'Download track',
    'url.load' => 'Load URL',
    'load' => 'Load music',
    'lyrics' => 'Find lyrics',
    'plugin.call' => 'Run plugin command',
    _ => operation.replaceAll('.', ' · ').replaceAll('_', ' '),
  };
}
