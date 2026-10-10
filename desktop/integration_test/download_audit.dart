import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  final directory = await Directory.systemTemp.createTemp(
    'cliamp-download-audit-',
  );
  final source = File('${a.root}/profile/home/Music/Aurora - Blue Hour.wav');
  final temporary = await source.copy('${directory.path}/Audit download.wav');
  try {
    await a.nav(t, 'Queue');
    await a.stage(t, 'save-downloaded-track-and-repeat', () async {
      await i.loadSources(t, temporary.path, replace: true);
      expect((await a.backend.snapshot())['track']['path'], temporary.path);
      if (find.byTooltip('Pause').evaluate().isEmpty) {
        await a.click(
          t,
          find.byTooltip('Play Audit download'),
          'Play downloaded fixture',
        );
      }
      await a.waitFor(t, find.byTooltip('Pause'));
      await a.click(t, find.byTooltip('Pause'), 'Pause downloaded fixture');
      for (var count = 0; count < 2; count++) {
        await a.click(
          t,
          find.byTooltip('Download current track'),
          'Save downloaded track',
        );
        await a.waitFor(t, find.textContaining('Saved to '));
        final saved = File(
          '${a.profilePath}/home/Music/cliamp/Audit download.wav',
        );
        expect(await saved.exists(), isTrue);
        expect(await saved.readAsBytes(), await temporary.readAsBytes());
      }
      await a.click(
        t,
        find.byTooltip('Background activity'),
        'Inspect completed download',
      );
      await a.waitFor(t, find.text('Download track'));
      await a.dialogSizes(t, 'download-activity');
      await a.click(t, find.text('Close'), 'Close download activity');
      expect(await temporary.readAsBytes(), await source.readAsBytes());
    });
  } finally {
    await a.nav(t, 'Queue');
    await i.loadSources(
      t,
      '${a.root}/profile/home/Music/list.m3u',
      replace: true,
    );
    await directory.delete(recursive: true);
  }
}
