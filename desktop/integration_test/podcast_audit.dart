import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://127.0.0.1:${server.port}';
  final audio = await File(
    '${a.root}/profile/home/Music/Aurora - Blue Hour.wav',
  ).readAsBytes();
  server.listen((request) async {
    if (request.uri.path.endsWith('.wav')) {
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.add(audio);
    } else {
      request.response.headers.contentType = ContentType(
        'application',
        'rss+xml',
        charset: 'utf-8',
      );
      request.response.write('''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Audit Podcast</title><description>Local QA fixture</description><link>$base</link>
<item><title>First Café 春 episode</title><guid>audit-one</guid><pubDate>Fri, 09 Oct 2026 00:00:00 GMT</pubDate><enclosure url="$base/one.wav" length="${audio.length}" type="audio/wav"/></item>
<item><title>Second episode</title><guid>audit-two</guid><pubDate>Thu, 08 Oct 2026 00:00:00 GMT</pubDate><enclosure url="$base/two.wav" length="${audio.length}" type="audio/wav"/></item>
</channel></rss>''');
    }
    await request.response.close();
  });
  Future<void> subscriptions() async {
    await a.nav(t, 'Providers');
    await i.choose(t, find.byType(DropdownButton<String>).first, 'Podcasts');
    await a.click(
      t,
      find.widgetWithText(ActionChip, 'Subscriptions'),
      'Podcast subscriptions',
    );
    await a.waitFor(t, find.byTooltip('Episode actions'));
  }

  try {
    await a.stage(t, 'podcast-feed-search-subscribe-open', () async {
      await a.nav(t, 'Providers');
      await i.choose(t, find.byType(DropdownButton<String>).first, 'Podcasts');
      await i.enter(t, find.byType(TextField), '$base/feed.xml');
      await a.key(t, LogicalKeyboardKey.enter);
      await a.waitFor(t, find.text('Audit Podcast'));
      await a.click(
        t,
        find.byTooltip('Add favorite').first,
        'Subscribe feed result',
      );
      await a.waitFor(t, find.byTooltip('Remove favorite'));
      await a.click(
        t,
        find.textContaining('Audit Podcast'),
        'Open podcast show',
      );
      await a.waitFor(t, find.text('First Café 春 episode'));
      await a.dialogSizes(t, 'podcast-episodes');
      await i.menu(t, 'Track actions', 'Track details');
      await a.click(t, find.text('Close'), 'Close episode details');
      await a.click(
        t,
        find.text('Add collection to queue'),
        'Append podcast collection',
      );
      await i.menu(t, 'Track actions', 'Add to queue');
      await i.menu(t, 'Track actions', 'Play next');
      await a.click(
        t,
        find.byTooltip('Back to previous collection'),
        'Back to feed result',
      );
    });
    await a.stage(t, 'podcast-all-subscription-actions', () async {
      await subscriptions();
      expect(find.text('1 subscription'), findsOneWidget);
      await a.click(
        t,
        find.text('Add newest from all shows'),
        'Newest from all shows',
      );
      await a.click(t, find.text('Play newest next'), 'Newest all next');
      for (final action in [
        'Add all episodes',
        'Queue all episodes next',
        'Add newest episode',
        'Play newest episode next',
        'Play episodes',
      ]) {
        await i.menu(t, 'Episode actions', action);
      }
      await subscriptions();
      // Episode menus live in Subscriptions; subscription toggles live in the
      // provider's playlist/catalog rows, which expose favorite capabilities.
      await a.click(
        t,
        find.widgetWithText(ActionChip, 'Playlists'),
        'Show subscription favorite controls',
      );
      await a.waitFor(t, find.byTooltip('Remove favorite'));
      await a.click(
        t,
        find.byTooltip('Remove favorite').first,
        'Unsubscribe fixture show',
      );
      await a.click(
        t,
        find.widgetWithText(ActionChip, 'Subscriptions'),
        'Check empty subscriptions',
      );
      await a.waitFor(t, find.text('No subscribed shows yet'));
    });
  } finally {
    await server.close(force: true);
  }
  await a.nav(t, 'Queue');
  await i.loadSources(
    t,
    '${a.root}/profile/home/Music/list.m3u',
    replace: true,
  );
}
