import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/person.dart';

import '../support/harness.dart';

/// The app at twice the type size.
///
/// Parents keeping a child's appointments and grandparents keeping their own
/// are the same audience, and the second half of it turns the system font up.
/// An overflow is a framework error, so nothing has to be asserted here: the
/// test fails by itself if a row, a chip or a button no longer fits. What the
/// walk has to do is visit the screens.
bool _isOccurrence(Key key) =>
    key is ValueKey<String> && key.value.startsWith('occurrence-');

void main() {
  final family = [
    Person(id: 'mila', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
    Person(
      id: 'sara',
      name: 'Sara',
      dateOfBirth: DateTime.utc(1988, 6, 30),
      sex: Sex.female,
    ),
  ];

  for (final scale in [1.5, 2.0]) {
    appTest('the family list and a timeline hold at $scale', people: family, (
      tester,
      db,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);

      expect(find.text('Mila'), findsOneWidget);

      await tester.tap(find.text('Mila'));
      await settle(tester);
      // Down the whole timeline, which is where a long title next to a
      // status chip runs out of room first.
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
        await settle(tester);
      }

      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w.key is ValueKey<String> && _isOccurrence(w.key!),
            )
            .first,
      );
      await settle(tester);
      await scrollTo(tester, find.byKey(const Key('mark-done')));
    });

    appTest('the settings and the sources hold at $scale', people: family, (
      tester,
      db,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);

      await tester.tap(find.byKey(const Key('open-settings')));
      await settle(tester);
      await scrollTo(tester, find.byKey(const Key('open-sources')));
      await tester.tap(find.byKey(const Key('open-sources')));
      await settle(tester);
      await scrollTo(tester, find.text('This is not medical advice'));
    });

    appTest('the form and the sync screen hold at $scale', people: family, (
      tester,
      db,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);

      await tester.tap(find.byKey(const Key('add-person')));
      await settle(tester);
      // The whole form, down to the optional vaccinations and the button.
      await scrollTo(tester, find.byKey(const Key('save-person')));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);

      await tester.tap(find.byKey(const Key('open-sync')));
      await settle(tester);
      await scrollTo(tester, find.byKey(const Key('import-bundle')));
    });
  }

  appTest(
    'the German text, which is longer, holds at 2.0',
    people: family,
    locale: const Locale('de'),
    (tester, db) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);

      expect(find.text('Familie'), findsOneWidget);
      await tester.tap(find.text('Mila'));
      await settle(tester);
      await scrollTo(tester, find.text('Demnächst'));
    },
  );
}
