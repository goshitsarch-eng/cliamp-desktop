import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  final config = File('${a.profilePath}/config/cliamp/config.toml');
  final original = await config.readAsBytes();
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final url = 'http://127.0.0.1:${listener.port}';
  await listener.close();
  try {
    await a.stage(t, 'provider-save-failure-and-offline-save', () async {
      await a.nav(t, 'Settings');
      await a.reveal(t, find.text('Connect service'));
      await a.click(t, find.text('Connect service'), 'Connect service');
      await i.choose(
        t,
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Music service',
        ),
        'Lyrion Music Server',
      );
      await i.enter(t, i.field('Server URL *'), url);
      await a.click(t, find.text('Save provider'), 'Verify unavailable server');
      await a.waitFor(t, find.text('Save without connection check'));
      expect(await config.readAsBytes(), original);
      await a.dialogSizes(t, 'provider-connection-error');
      await a.click(
        t,
        find.text('Save without connection check'),
        'Save offline',
      );
      await a.waitFor(t, find.text('Your provider is configured'));
      expect(await config.readAsString(), contains(url));
      await a.dialogSizes(t, 'provider-saved');
      await a.click(t, find.text('Later'), 'Defer provider restart');
      expect(find.text('Your provider is configured'), findsNothing);
    });
  } finally {
    // This disposable profile must remain usable by the later restart checks.
    await config.writeAsBytes(original);
  }
}
