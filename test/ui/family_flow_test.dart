import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/person.dart';

import '../support/harness.dart';

void main() {
  // Nineteen days old on the pinned today, which puts the U2 past its
  // exclusion deadline, the U3 open, and everything else ahead.
  final newborn = Person(
    id: 'anna',
    name: 'Anna',
    dateOfBirth: DateTime.utc(2026, 9, 1),
  );

  Future<void> openTimeline(WidgetTester tester) async {
    await tester.tap(find.text('Anna'));
    await settle(tester);
  }

  /// The optional vaccinations push the save button below the fold.
  Future<void> saveForm(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.byKey(const Key('save-person')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('save-person')));
    await settle(tester);
  }

  appTest('an empty family says what to do next', (tester, db) async {
    expect(find.text('No one here yet'), findsOneWidget);
    expect(find.byKey(const Key('add-person')), findsOneWidget);
  });

  appTest('the form refuses to save without a name or a birth date', (
    tester,
    db,
  ) async {
    await tester.tap(find.byKey(const Key('add-person')));
    await settle(tester);
    await saveForm(tester);
    // The refused save leaves the form scrolled to its button; the errors
    // are back at the top.
    await tester.drag(find.byType(ListView), const Offset(0, 4000));
    await settle(tester);

    expect(find.text('Please enter a name'), findsOneWidget);
    expect(find.text('Please pick a date of birth'), findsOneWidget);
  });

  appTest('a person added through the form appears on the list', (
    tester,
    db,
  ) async {
    await tester.tap(find.byKey(const Key('add-person')));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('person-name')), 'Anna');
    await tester.tap(find.byKey(const Key('pick-date-of-birth')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), '09012026');
    await tester.tap(find.byKey(const Key('date-input-ok')));
    await settle(tester);

    await saveForm(tester);

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('19 days old'), findsOneWidget);
    expect((await db.allPersons()).single.name, 'Anna');
  });

  appTest(
    'a newborn gets the check-ups grouped by what needs doing',
    people: [newborn],
    (tester, db) async {
      await openTimeline(tester);

      // At nineteen days old the U1 is late, the U3 has not opened yet, and
      // the U2 is past its exclusion deadline.
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('U1'), findsOneWidget);

      await scrollTo(tester, find.text('U3'));
      expect(find.text('U3'), findsOneWidget);
      expect(find.text('Upcoming'), findsWidgets);

      await scrollTo(tester, find.text('U2'));
      expect(find.text('U2'), findsOneWidget);
      expect(find.text('Expired'), findsWidgets);
    },
  );

  appTest(
    'an appointment names its source and the date it was reviewed',
    people: [newborn],
    (tester, db) async {
      await openTimeline(tester);
      await scrollTo(tester, find.text('U6'));
      await tester.tap(find.text('U6'));
      await settle(tester);

      expect(
        find.textContaining('G-BA guideline on early detection'),
        findsOneWidget,
      );
      expect(find.textContaining('as of September 20, 2026'), findsOneWidget);
      expect(find.text('Catch up by'), findsOneWidget);
    },
  );

  appTest(
    'recording an appointment settles it and can be undone',
    people: [newborn],
    (tester, db) async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u3',
          completedOn: DateTime.utc(2026, 9, 25),
        ),
      );
      await settle(tester);
      await openTimeline(tester);
      await scrollTo(tester, find.text('Done and skipped'));
      await tester.tap(find.text('U3'));
      await settle(tester);

      expect(find.text('Done'), findsOneWidget);
      expect(find.byKey(const Key('mark-done')), findsNothing);

      await tester.tap(find.byKey(const Key('undo-record')));
      await settle(tester);
      expect(await db.allCompletions(), isEmpty);
    },
  );

  appTest(
    'U10 is labelled as depending on the insurer',
    people: [
      Person(id: 'kid', name: 'Kind', dateOfBirth: DateTime.utc(2019, 1, 1)),
    ],
    (tester, db) async {
      await tester.tap(find.text('Kind'));
      await settle(tester);
      await scrollTo(tester, find.text('U10'));

      expect(find.text('Depends on your insurer'), findsWidgets);
    },
  );

  appTest('the sources screen lists the sources and the disclaimer', (
    tester,
    db,
  ) async {
    await tester.tap(find.byKey(const Key('open-settings')));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('open-sources')), 300);
    await settle(tester);
    await tester.tap(find.byKey(const Key('open-sources')));
    await settle(tester);

    expect(
      find.textContaining("Children's check-ups, version"),
      findsOneWidget,
    );
    expect(
      find.textContaining('G-BA guideline on early detection'),
      findsOneWidget,
    );

    await scrollTo(tester, find.text('This is not medical advice'));
    expect(find.text('Your data stays here'), findsOneWidget);
  });

  appTest(
    'the app renders in German',
    people: [newborn],
    locale: const Locale('de'),
    (tester, db) async {
      expect(find.text('Familie'), findsOneWidget);
      await openTimeline(tester);
      expect(find.text('Jetzt dran'), findsOneWidget);
      await scrollTo(tester, find.text('Demnächst'));
      expect(find.text('Demnächst'), findsWidgets);
    },
  );
}
