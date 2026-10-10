import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_audit_test.dart' as a;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Finder hint(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == label,
);
Future<void> enter(WidgetTester t, Finder f, String value) async {
  await a.waitFor(t, f);
  await t.ensureVisible(f.first);
  await a.click(t, f.first, 'Focus text input');
  await Clipboard.setData(ClipboardData(text: value));
  for (final key in ['a', value.isEmpty ? 'BackSpace' : 'v']) {
    final r = await Process.run('python3', [
      '${a.root}/window.py',
      'key',
      a.window,
      if (key != 'BackSpace') 'Control_L',
      key,
    ]);
    expect(r.exitCode, 0);
    await a.tick(t, 100);
  }
  await a.tick(t);
  final widget = t.widget<TextField>(f.first);
  final expected = widget.maxLines == 1 ? value.replaceAll('\n', '') : value;
  expect(
    t
        .widget<EditableText>(
          find.descendant(of: f.first, matching: find.byType(EditableText)),
        )
        .controller
        .text,
    expected,
    reason: 'Native text input must update the field',
  );
  a.results.add({
    'stage': a.current,
    'action': 'paste-text',
    'characters': value.length,
  });
}

Future<void> menu(
  WidgetTester t,
  String tooltip,
  String item, {
  int index = 0,
}) async {
  await a.click(t, find.byTooltip(tooltip).at(index), tooltip);
  await a.click(t, find.widgetWithText(PopupMenuItem<String>, item), item);
}

Future<void> choose(WidgetTester t, Finder dropdown, String option) async {
  final widget = t.widget(dropdown.first);
  final picker = widget is DropdownButton
      ? widget
      : t.widget<DropdownButton>(
          find.descendant(
            of: dropdown,
            matching: find.byWidgetPredicate((w) => w is DropdownButton),
          ),
        );
  final selected = picker.items!.indexWhere(
    (item) => item.value == picker.value,
  );
  final target = picker.items!.indexWhere(
    (item) => item.child is Text && (item.child as Text).data == option,
  );
  expect(
    target,
    greaterThanOrEqualTo(0),
    reason: 'Dropdown option must exist: $option',
  );
  await a.click(t, dropdown, 'Open dropdown');
  final scroll = find.byType(Scrollable).last;
  final item = find.descendant(of: scroll, matching: find.text(option));
  await t.scrollUntilVisible(
    item,
    target < selected ? -180 : 180,
    scrollable: scroll,
    maxScrolls: 45,
  );
  await a.click(t, item, 'Select $option');
}

Future<void> loadSources(
  WidgetTester t,
  String text, {
  bool replace = false,
}) async {
  await a.key(t, LogicalKeyboardKey.keyO, ctrl: true);
  if (replace) {
    await a.click(t, find.text('Replace queue'), 'Replace queue mode');
  }
  await enter(t, field('File, folder, playlist, URL, or ssh:// path'), text);
  await a.click(t, find.text('Continue'), 'Continue import');
  if (find.text('Replace the queue?').evaluate().isNotEmpty) {
    await a.click(t, find.text('Replace'), 'Confirm replace');
  }
  await a.tick(t, 1800);
}

Future<void> exercise(WidgetTester t) async {
  await a.nav(t, 'Queue');
  await a.stage(t, 'source-empty-validation', () async {
    await a.key(t, LogicalKeyboardKey.keyO, ctrl: true);
    await enter(
      t,
      field('File, folder, playlist, URL, or ssh:// path'),
      '   \n ',
    );
    await a.click(t, find.text('Continue'), 'Continue empty');
    expect(
      find.text('Enter a source or choose files or folders.'),
      findsOneWidget,
    );
    await a.click(t, find.text('Cancel'), 'Cancel');
  });
  final music = '${a.root}/profile/home/Music';
  await a.stage(t, 'import-local-unicode-multiline', () async {
    await loadSources(
      t,
      '$music/Aurora - Blue Hour.wav\n$music/Björk Test - Café 春.wav',
    );
    expect(find.byTooltip('Track actions'), findsNWidgets(2));
  });
  await a.stage(t, 'queue-search-empty-unicode-clear', () async {
    await enter(t, hint('Search your music…'), 'nonexistent Æ 春' * 10);
    expect(find.text('No matching tracks'), findsOneWidget);
    await a.click(t, find.byTooltip('Clear search'), 'Clear search');
    await enter(t, hint('Search your music…'), 'Café');
    expect(find.byTooltip('Track actions'), findsOneWidget);
    await a.click(t, find.byTooltip('Clear search'), 'Clear search');
    await a.key(t, LogicalKeyboardKey.escape);
  });
  await a.stage(t, 'queue-track-details-and-move', () async {
    await menu(t, 'Track actions', 'Track details');
    expect(find.text('Title'), findsOneWidget);
    await a.dialogSizes(t, 'track-details');
    await a.click(t, find.text('Close'), 'Close details');
    await menu(t, 'Track actions', 'Move down');
    await menu(t, 'Track actions', 'Move up', index: 1);
    await a.click(t, find.byTooltip('Undo last queue edit'), 'Undo move');
    await menu(t, 'Track actions', 'Play next');
    await a.nav(t, 'Play next');
    expect(find.byTooltip('Track actions'), findsOneWidget);
    await menu(t, 'Track actions', 'Remove from list');
    expect(find.byTooltip('Track actions'), findsNothing);
    await a.nav(t, 'Queue');
  });
  await a.stage(t, 'favorites-add-open-remove', () async {
    await a.click(t, find.byTooltip('Add favorite').first, 'Add favorite');
    await a.nav(t, 'Favorites');
    expect(find.byTooltip('Track actions'), findsOneWidget);
    await a.click(t, find.byTooltip('Remove favorite'), 'Remove favorite');
    await a.nav(t, 'Queue');
  });
  await a.stage(t, 'queue-selection-cancel-and-resize', () async {
    await a.click(t, find.byTooltip('Select tracks'), 'Select tracks');
    await a.click(t, find.text('Select visible'), 'Select visible');
    expect(find.text('2 selected'), findsOneWidget);
    await a.resize(t, 640, 480);
    await a.capture('selected-640x480');
    await a.resize(t, 1280, 940);
    await a.click(t, find.text('Remove').first, 'Remove selection');
    await a.click(t, find.text('Cancel'), 'Cancel removal');
    await a.click(t, find.byTooltip('Finish selecting'), 'Finish selecting');
    expect(find.byTooltip('Track actions'), findsNWidgets(2));
  });
  await playback(t);
  await a.stage(t, 'equalizer-presets-and-bands', () async {
    await a.nav(t, 'Equalizer');
    final dd = find.byType(DropdownButton<String>);
    final presets = t
        .widget<DropdownButton<String>>(dd)
        .items!
        .map((e) => e.value!)
        .toList();
    for (final preset in presets.where((p) => p != 'Custom')) {
      await choose(t, dd, preset);
      final state = await a.backend.snapshot();
      expect(state['eq_preset'], preset);
    }
    await choose(t, dd, 'Flat');
    final sliders = find.byType(Slider);
    // The ten rotated band sliders precede the player volume and seek controls.
    for (var i = 0; i < 10; i++) {
      await t.ensureVisible(sliders.at(i));
      await t.drag(sliders.at(i), const Offset(0, -25));
      await a.tick(t);
      final state = await a.backend.snapshot();
      expect((state['eq_bands'] as List)[i], isNot(0));
      a.results.add({'stage': a.current, 'action': 'drag-band', 'index': i});
    }
    await choose(t, dd, 'Custom');
    expect((await a.backend.snapshot())['eq_preset'], 'Custom');
    await choose(t, dd, 'Flat');
  });
  await preferences(t);
  await setup(t);
}

Future<void> preferences(WidgetTester t) async {
  await a.nav(t, 'Settings');
  await a.click(t, find.text('All preferences'), 'All preferences');
  await a.waitFor(t, find.text('Playback'));
  final schema = await a.backend.preferencesSchema();
  var active = Platform.environment['CLIAMP_AUDIT_PREFERENCE_START'] == null;
  for (final item in schema['fields'] as List) {
    if ((item as Map)['key'] ==
        Platform.environment['CLIAMP_AUDIT_PREFERENCE_START']) {
      active = true;
    }
    if (!active) continue;
    final f = Map<String, dynamic>.from(item);
    await a.stage(t, 'preference-${f['key']}', () async {
      await enter(t, hint('Find a preference'), '${f['key']}');
      final label = '${f['label']}';
      if (f['type'] == 'bool') {
        final sw = find.widgetWithText(SwitchListTile, label);
        await a.click(t, sw, 'Toggle $label');
        await a.click(t, sw, 'Restore $label');
      } else if ((f['options'] as List? ?? []).isNotEmpty) {
        final dd = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == label,
        );
        for (final option in f['options'] as List) {
          await choose(t, dd, '$option'.isEmpty ? 'Default' : '$option');
        }
        await choose(
          t,
          dd,
          '${f['value']}'.isEmpty ? 'Default' : '${f['value']}',
        );
      } else {
        await enter(t, field(label), '');
        await enter(
          t,
          field(label),
          '  Café 春 ! /tmp/music \n${'long ' * 100}',
        );
        await enter(t, field(label), '${f['value']}');
      }
      await a.resize(t, 640, 480);
      await a.capture('preference-${f['key']}-minimum');
      await a.resize(t, 1280, 940);
    });
  }
  await a.stage(t, 'preferences-validation-and-save', () async {
    await enter(t, hint('Find a preference'), 'volume_min');
    await enter(t, field('Volume min'), '999');
    await a.click(t, find.text('Save changes'), 'Reject invalid preference');
    await a.tick(t, 800);
    expect(find.textContaining('outside the supported range'), findsWidgets);
    await a.dialogSizes(t, 'preferences-invalid');
    await enter(t, field('Volume min'), '-48');
    await a.click(t, find.text('Save changes'), 'Save preference');
    await a.tick(t, 800);
    expect(find.textContaining('Saved.'), findsOneWidget);
    await a.click(t, find.text('Done'), 'Done preferences');
    await a.click(t, find.text('All preferences'), 'Reopen preferences');
    await enter(t, hint('Find a preference'), 'volume_min');
    expect(t.widget<TextField>(field('Volume min')).controller!.text, '-48');
    await a.click(t, find.text('Done'), 'Done preferences');
  });
}

Future<void> setup(WidgetTester t) async {
  await a.nav(t, 'Settings');
  await a.reveal(t, find.text('Connect service'));
  await a.click(t, find.text('Connect service'), 'Connect service');
  final schema = jsonDecode(
    await File('${a.root}/setup-schema.json').readAsString(),
  );
  for (final p in schema['providers'] as List) {
    await a.stage(t, 'setup-${p['key']}', () async {
      final dd = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Music service',
      );
      await choose(t, dd, '${p['name']}');
      await a.tick(t, 700);
      await a.resize(t, 640, 480);
      await a.capture('setup-${p['key']}-minimum');
      await a.resize(t, 1280, 940);
      final connectionPicker = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText != 'Music service',
      );
      final choices = connectionPicker.evaluate().isEmpty
          ? <String>[]
          : t
                .widget<DropdownButton<String>>(
                  find.descendant(
                    of: connectionPicker,
                    matching: find.byType(DropdownButton<String>),
                  ),
                )
                .items!
                .map((item) => (item.child as Text).data!)
                .toList();
      final testedFields = <String>{};
      for (final choice in choices.isEmpty ? <String?>[null] : choices) {
        if (choice != null) await choose(t, connectionPicker, choice);
        final inputs = find.byType(TextFormField);
        for (var i = 0; i < inputs.evaluate().length; i++) {
          final tf = find.descendant(
            of: inputs.at(i),
            matching: find.byType(TextField),
          );
          if (tf.evaluate().isNotEmpty) {
            final label = t.widget<TextField>(tf).decoration?.labelText ?? '$i';
            if (!testedFields.add(label)) continue;
            await enter(t, tf, 'Café 春 !');
            await enter(t, tf, '');
          }
        }
        // Required-field validation is local; no real accounts or credentials are submitted.
        final required = t
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextField),
              ),
            )
            .any((w) => w.decoration?.labelText?.endsWith(' *') ?? false);
        if (required) {
          await a.click(
            t,
            find.text('Save provider'),
            'Validate required provider fields',
          );
          await a.tick(t, 700);
          expect(find.text('This field is required.'), findsWidgets);
        }
      }
    });
  }
  await a.click(t, find.text('Cancel'), 'Cancel provider setup');
}

Future<void> playback(WidgetTester t) async {
  await a.stage(t, 'play-pause-seek-controls', () async {
    final plays = find.byWidgetPredicate(
      (w) =>
          w is Tooltip &&
          (w.message?.startsWith('Play ') ?? false) &&
          w.message != 'Play next',
    );
    await a.click(t, plays.first, 'Play first track');
    await a.waitFor(t, find.byTooltip('Pause'));
    await a.click(t, find.byTooltip('Pause'), 'Pause');
    await a.key(t, LogicalKeyboardKey.keyJ, ctrl: true);
    await enter(t, field('Time'), '-1');
    await a.click(t, find.text('Jump'), 'Reject negative seek');
    expect(find.textContaining('Enter a nonnegative time'), findsOneWidget);
    await enter(t, field('Time'), '1:00');
    await a.click(t, find.text('Jump'), 'Seek one minute');
    expect(find.text('Jump to time'), findsNothing);
    final state = await a.backend.snapshot();
    expect((state['position'] as num).toDouble(), closeTo(60, 1));
    a.results.add({'stage': a.current, 'stateAfterSeek': state});
    await a.click(t, find.byTooltip('Shuffle'), 'Shuffle on');
    await a.click(t, find.byTooltip('Shuffle'), 'Shuffle off');
    await menu(t, 'Playback options', 'Switch to mono');
    await menu(t, 'Playback options', 'Switch to stereo');
    await menu(t, 'Playback options', 'Toggle shuffle');
    await menu(t, 'Playback options', 'Toggle shuffle');
    await menu(t, 'Playback options', 'Adjust volume…');
    await a.dialogSizes(t, 'volume');
    await a.click(t, find.text('Cancel'), 'Cancel volume');
    final volumeBefore = (await a.backend.snapshot())['volume'];
    await menu(t, 'Playback options', 'Adjust volume…');
    await t.drag(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Slider),
      ),
      const Offset(-35, 0),
    );
    await a.tick(t);
    await a.click(t, find.text('Apply'), 'Apply dialog volume');
    expect((await a.backend.snapshot())['volume'], isNot(volumeBefore));
    for (var n = 0; n < 3; n++) {
      final repeat = (await a.backend.snapshot())['repeat'];
      await menu(t, 'Playback options', 'Repeat: $repeat');
    }
    final seek = find.byWidgetPredicate((w) => w is Slider && w.max != 6);
    final positionBefore = (await a.backend.snapshot())['position'];
    await t.drag(seek, const Offset(30, 0));
    await a.tick(t);
    expect((await a.backend.snapshot())['position'], isNot(positionBefore));
    await a.click(t, find.byTooltip('Show lyrics'), 'Lyrics player button');
    await a.nav(t, 'Queue');
    await menu(t, 'Playback options', 'Stop playback');
  });
}
