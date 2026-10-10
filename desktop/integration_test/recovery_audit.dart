import 'dart:io';
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
  await a.stage(t, 'owned-engine-exit-and-recovery', () async {
    final processes = await Process.run('ps', ['-eo', 'pid=,ppid=,args=']);
    final owned = '${processes.stdout}'.split('\n').where((line) {
      final match = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.+)$').firstMatch(line);
      return match != null &&
          int.parse(match.group(2)!) == pid &&
          match.group(3)!.endsWith(' --daemon');
    }).toList();
    expect(
      owned,
      hasLength(1),
      reason: 'Only terminate this audit app’s own daemon',
    );
    final child = int.parse(owned.single.trim().split(RegExp(r'\s+')).first);
    expect(Process.killPid(child, ProcessSignal.sigterm), isTrue);
    await a.tick(t, 800);
    await a.capture('engine-exit');
    for (var n = 0; n < 100; n++) {
      final retry = find.text('Retry connection');
      if (retry.evaluate().isNotEmpty) {
        await a.click(t, retry, 'Retry owned engine');
      }
      if (find.text('Engine connected').evaluate().isNotEmpty) break;
      await a.tick(t, 200);
    }
    await a.waitFor(t, find.text('Engine connected'));
    await i.loadSources(
      t,
      '${a.root}/profile/home/Music/list.m3u',
      replace: true,
    );
    expect((await a.backend.snapshot())['total'], 2);
    expect(find.byTooltip('Track actions'), findsNWidgets(2));
  });
}
