// Renders the main screens to PNGs for a visual review. Not part of the test
// gate: the output depends on a system font, and nothing here asserts.
//
//   flutter test tool/screenshots/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/person.dart';

import '../../test/support/harness.dart';

final _people = [
  Person(id: 'infant', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
  Person(
    id: 'school',
    name: 'Jonas',
    dateOfBirth: DateTime.utc(2018, 4, 12),
    sex: Sex.male,
  ),
  Person(
    id: 'mother',
    name: 'Sara',
    dateOfBirth: DateTime.utc(1988, 6, 30),
    sex: Sex.female,
  ),
];

Future<void> _loadFont() async {
  Future<ByteData> read(String path) async =>
      ByteData.view(File(path).readAsBytesSync().buffer);
  await (FontLoader(
    'Roboto',
  )..addFont(read('/usr/share/fonts/noto/NotoSans-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')..addFont(
        read(
          '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ))
      .load();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await settle(tester);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('out/$name.png'),
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  // scrollTo stops as soon as the text exists, which can be just below the
  // fold, where a tap lands on nothing.
  await tester.ensureVisible(find.text(text).first);
  await settle(tester);
  await tester.tap(find.text(text).first);
  await settle(tester);
}

void main() {
  setUpAll(_loadFont);

  appTest('family', people: _people, (tester, db) async {
    _phone(tester);
    await _shot(tester, '01-family');
    await _tapText(tester, 'Mila');
    await _shot(tester, '02-timeline-infant');
    await scrollTo(tester, find.text('U6'));
    await _tapText(tester, 'U6');
    await _shot(tester, '03-detail-u6');
    await _back(tester);
    await _back(tester);
    await _tapText(tester, 'Sara');
    await _shot(tester, '04-timeline-adult');
    await _back(tester);
    await tester.tap(find.byKey(const Key('open-settings')));
    await _shot(tester, '05-settings');
    await tester.tap(find.byKey(const Key('open-sources')));
    await _shot(tester, '06-sources');
    await _back(tester);
    await tester.tap(find.byKey(const Key('open-how-it-works')));
    await _shot(tester, '11-how-it-works');
  });

  appTest('empty and form', (tester, db) async {
    _phone(tester);
    await _shot(tester, '07-empty');
    await tester.tap(find.byKey(const Key('add-person')));
    await _shot(tester, '08-person-form');
  });

  appTest(
    'support prompt, german',
    people: _people,
    locale: const Locale('de'),
    (tester, db) async {
      _phone(tester);
      for (final rule in ['u3', 'u4', 'u5']) {
        await db.recordCompletion(
          Completion(
            personId: 'infant',
            ruleId: rule,
            completedOn: DateTime.utc(2026, 9, 20),
          ),
        );
      }
      await settle(tester);
      await _shot(tester, '09-family-de-support');
      await _tapText(tester, 'Mila');
      await _shot(tester, '10-timeline-de');
    },
  );
}
