import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requested = Completer<void>();
  final release = Completer<void>();
  server.listen((request) async {
    if (!requested.isCompleted) requested.complete();
    await release.future;
    try {
      request.response.write('#EXTM3U\n');
      await request.response.close();
    } catch (_) {
      /* Cancellation closes the HTTP client. */
    }
  });
  try {
    await a.stage(t, 'cancel-running-source-job', () async {
      final before = (await a.backend.snapshot())['total'];
      await a.key(t, LogicalKeyboardKey.keyO, ctrl: true);
      await i.enter(
        t,
        i.field('File, folder, playlist, URL, or ssh:// path'),
        'http://127.0.0.1:${server.port}/slow.m3u',
      );
      await a.click(
        t,
        find.text('Continue'),
        'Start slow import',
        waitForIdle: false,
      );
      await requested.future.timeout(const Duration(seconds: 10));
      await a.click(
        t,
        find.byTooltip('Background activity'),
        'Inspect running job',
        waitForIdle: false,
      );
      await a.waitFor(t, find.byTooltip('Cancel operation'));
      await a.dialogSizes(t, 'running-job');
      await a.click(
        t,
        find.byTooltip('Cancel operation'),
        'Cancel source operation',
        waitForIdle: false,
      );
      await a.waitFor(t, find.textContaining('Canceled ·'));
      await a.capture('canceled-job');
      expect(
        a.backend.currentJobs.any((job) => job.state == 'canceled'),
        isTrue,
      );
      await a.click(t, find.text('Close'), 'Close canceled activity');
      expect((await a.backend.snapshot())['total'], before);
    });
  } finally {
    release.complete();
    await server.close(force: true);
  }
}
