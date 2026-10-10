import 'package:cliamp_desktop/src/provider_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;
import 'interaction_audit.dart' as i;

Future<void> exercise(WidgetTester t) async {
  final providers =
      (await a.backend.call('provider.list'))['providers'] as List;
  await a.nav(t, 'Providers');
  for (final provider in providers) {
    await a.stage(t, 'browse-${provider['key']}', () async {
      final picker = find.byType(DropdownButton<String>).first;
      await i.choose(t, picker, '${provider['name']}');
      await a.tick(t, 800);
      await a.resize(t, 640, 480);
      await a.capture('provider-${provider['key']}-minimum');
      await a.resize(t, 1280, 940);
      final routes = t
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((c) => (c.label as Text).data!)
          .toList();
      for (final route in routes) {
        if (route == 'Local radio' &&
            find.widgetWithText(ActionChip, route).evaluate().isEmpty) {
          a.results.add({
            'stage': a.current,
            'route': route,
            'note':
                'Consent was already answered through the Use my location collection row; direct route is covered in the fresh location-allow phase.',
          });
          continue;
        }
        await a.click(
          t,
          find.widgetWithText(ActionChip, route),
          'Provider route $route',
        );
        if (route == 'Connect service') {
          await a.waitFor(t, find.text('Connect your music'));
          await a.click(t, find.text('Cancel'), 'Cancel provider setup');
          continue;
        }
        if (route == 'Local radio') {
          await a.click(
            t,
            find.text('Do not use location'),
            'Decline location',
          );
        }
        await a.tick(t, 800);
        await a.capture(
          'provider-${provider['key']}-${route.replaceAll(' ', '-')}',
        );
        a.results.add({
          'stage': a.current,
          'route': route,
          'visibleLabels': t
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(ProviderBrowser),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data)
              .whereType<String>()
              .toList(),
          'rowCount': find
              .descendant(
                of: find.byType(ProviderBrowser),
                matching: find.byType(ListTile),
              )
              .evaluate()
              .length,
        });
        final pins = find.byTooltip(RegExp(r'^Pin '));
        if (pins.evaluate().isNotEmpty) {
          final tooltip = t.widget(pins.first);
          final label = tooltip is Tooltip
              ? tooltip.message!
              : (tooltip as RawTooltip).semanticsTooltip!;
          await a.click(t, pins.first, 'Pin category');
          await a.click(
            t,
            find.byTooltip(label.replaceFirst('Pin ', 'Unpin ')),
            'Unpin category',
          );
          await a.click(
            t,
            find.widgetWithText(FilterChip, 'Pinned only'),
            'Pinned categories only',
          );
          await a.click(
            t,
            find.widgetWithText(FilterChip, 'Pinned only'),
            'All categories',
          );
        }
        var depth = 0;
        for (; depth < 2; depth++) {
          final rows = find.descendant(
            of: find.byType(ProviderBrowser),
            matching: find.byType(ListTile),
          );
          if (rows.evaluate().isEmpty) break;
          await a.click(t, rows.first, 'Open provider collection level $depth');
          await a.tick(t, 800);
          if (find.text('Allow location').evaluate().isNotEmpty) {
            await a.click(
              t,
              find.text('Do not use location'),
              'Decline location from collection row',
            );
            depth = 0;
            break;
          }
          if (find.byType(ProviderBrowser).evaluate().isEmpty) {
            await a.waitFor(t, find.text('Your queue'));
            final playback = await a.backend.snapshot();
            expect(playback['total'], greaterThan(0));
            a.results.add({'stage': a.current, 'collectionPlayback': playback});
            await a.nav(t, 'Providers');
            await i.choose(
              t,
              find.byType(DropdownButton<String>).first,
              '${provider['name']}',
            );
            depth = 0;
            break;
          }
        }
        if (depth > 0) {
          await a.dialogSizes(t, 'provider-${provider['key']}-collection');
          if (provider['key'] == 'cliamp') {
            await a.resize(t, 640, 480);
            final browser = find.byType(ProviderBrowser);
            final scroll = find
                .descendant(
                  of: browser,
                  matching: find.byType(SingleChildScrollView),
                )
                .first;
            await t.drag(scroll, const Offset(0, -140));
            await a.tick(t);
            final row = find
                .descendant(of: browser, matching: find.byType(ListTile))
                .first;
            final bounds = t.getRect(browser);
            final rowBounds = t.getRect(row);
            expect(rowBounds.top, greaterThanOrEqualTo(bounds.top));
            expect(rowBounds.bottom, lessThanOrEqualTo(bounds.bottom));
            await a.capture('provider-collection-scrolled-minimum');
            await a.resize(t, 1280, 940);
          }

          final sorts = find.descendant(
            of: find.byType(ProviderBrowser),
            matching: find.byType(DropdownButton<String>),
          );
          if (sorts.evaluate().isNotEmpty) {
            final labels = t
                .widget<DropdownButton<String>>(sorts)
                .items!
                .map((item) => (item.child as Text).data!)
                .toList();
            for (final label in labels) {
              await i.choose(t, sorts, label);
            }
          }
          final more = find.textContaining('Load more');
          if (more.evaluate().isNotEmpty) {
            await a.click(t, more, 'Load additional provider rows');
            await a.tick(t, 800);
          }
          final append = find.text('Add collection to queue');
          if (append.evaluate().isNotEmpty) {
            await a.click(t, append, 'Append public provider collection');
            await a.waitFor(t, find.text('Added the collection to the queue.'));
          }
          final play = find.widgetWithText(FilledButton, 'Play collection');
          if (play.evaluate().isNotEmpty) {
            await a.click(t, play, 'Play public collection');
            await a.waitFor(t, find.text('Your queue'));
            final playback = await a.backend.snapshot();
            expect(playback['total'], greaterThan(0));
            a.results.add({'stage': a.current, 'collectionPlayback': playback});
            await a.nav(t, 'Providers');
            await i.choose(
              t,
              find.byType(DropdownButton<String>).first,
              '${provider['name']}',
            );
          }
          for (var n = 0; n < depth; n++) {
            final back = find.byTooltip('Back to previous collection');
            if (back.evaluate().isEmpty) break;
            await a.click(t, back, 'Back from provider collection');
          }
        }
      }
      final search = find.byType(TextField).first;
      await i.enter(t, search, 'no matches Café 春');
      await a.key(t, LogicalKeyboardKey.enter);
      await a.tick(t, 1500);
      await a.capture('provider-${provider['key']}-search');
      await a.key(t, LogicalKeyboardKey.escape);
      expect(
        t.widget<TextField>(search).controller!.text,
        isEmpty,
        reason: 'Escape exits provider search',
      );
      await i.enter(t, search, '');
      final refresh = find.byTooltip('Reload collection').evaluate().isNotEmpty
          ? find.byTooltip('Reload collection')
          : find.byTooltip('Refresh provider from source');
      if (refresh.evaluate().isNotEmpty) {
        await a.click(t, refresh, 'Reload provider');
      }
      a.results.add({'stage': a.current, 'routes': routes});
    });
  }
}

Future<void> locationConsent(WidgetTester t) async {
  await a.stage(t, 'native-location-dismiss-and-allow', () async {
    await a.nav(t, 'Providers');
    await i.choose(t, find.byType(DropdownButton<String>).first, 'Radio');
    final route = find.widgetWithText(ActionChip, 'Local radio');
    await a.click(t, route, 'Open location consent');
    await a.waitFor(t, find.text('Allow location'));
    await a.dialogSizes(t, 'radio-location-consent');
    await a.key(t, LogicalKeyboardKey.escape);
    expect(find.text('Allow location'), findsNothing);
    await a.click(t, route, 'Reopen unanswered location consent');
    await a.click(t, find.text('Allow location'), 'Allow cloud test location');
    await a.waitFor(t, find.textContaining('Local radio'));
    final state = await a.backend.call('provider.location', {
      'provider': 'radio',
    });
    a.results.add({'stage': a.current, 'locationResult': state});
    expect((state['location'] as Map)['needed'], isFalse);
  });
}
