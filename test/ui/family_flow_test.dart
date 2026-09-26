import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/person.dart';

import '../support/harness.dart';
import '../support/recording_gateway.dart';

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

      // At nineteen days old the blood screening is late but can still be
      // caught up, the U3 has not opened yet, and the U1 and U2 have lapsed.
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Extended newborn screening'), findsOneWidget);

      await scrollTo(tester, find.text('U3'));
      expect(find.text('U3'), findsOneWidget);
      expect(find.text('Upcoming'), findsWidgets);

      await scrollTo(tester, find.text('U2'));
      expect(find.text('U2'), findsOneWidget);
      expect(find.text('Expired'), findsWidgets);
      await scrollTo(tester, find.text('U1'));
      expect(find.text('U1'), findsOneWidget);
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
      await scrollTo(tester, find.text('U3'));
      await tester.ensureVisible(find.text('U3'));
      await settle(tester);
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
    'the page follows a booster it records and undoes',
    people: [
      Person(id: 'sara', name: 'Sara', dateOfBirth: DateTime.utc(1988, 6, 30)),
    ],
    (tester, db) async {
      await tester.tap(find.text('Sara'));
      await settle(tester);
      await scrollTo(tester, find.text('Tetanus and diphtheria booster'));
      await tester.tap(find.text('Tetanus and diphtheria booster'));
      await settle(tester);

      await tester.tap(find.byKey(const Key('mark-done')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('date-input')), '03152026');
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await settle(tester);

      expect(find.text('Tetanus and diphtheria booster'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect((await db.allCompletions()).single.ruleId, 'td-booster');

      await tester.tap(find.byKey(const Key('undo-record')));
      await settle(tester);
      expect(find.text('Tetanus and diphtheria booster'), findsOneWidget);
      expect(find.byKey(const Key('mark-done')), findsOneWidget);
      expect(await db.allCompletions(), isEmpty);
    },
  );

  appTest('a dog added through the form gets the dog catalog', (
    tester,
    db,
  ) async {
    await tester.tap(find.byKey(const Key('add-person')));
    await settle(tester);
    await tester.tap(find.text('Dog'));
    await settle(tester);
    // The help about screenings for people is not shown for an animal.
    expect(find.textContaining('screenings someone is entitled'), findsNothing);

    await tester.enterText(find.byKey(const Key('person-name')), 'Bello');
    await tester.tap(find.byKey(const Key('pick-date-of-birth')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), '07202026');
    await tester.tap(find.byKey(const Key('date-input-ok')));
    await settle(tester);

    await tester.dragUntilVisible(
      find.byKey(const Key('optional-dog-deworming')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Depending on how the animal lives'), findsOneWidget);
    expect(find.byKey(const Key('optional-dog-deworming')), findsOneWidget);
    expect(find.byKey(const Key('optional-tbe')), findsNothing);
    await saveForm(tester);

    expect((await db.allPersons()).single.species, Species.dog);
    expect(find.byIcon(Icons.pets), findsOneWidget);

    await tester.tap(find.text('Bello'));
    await settle(tester);
    expect(find.text('Distemper and parvovirus · dose 1 of 4'), findsOneWidget);
    expect(find.text('U6'), findsNothing);
  });

  appTest(
    'the family list says when notifications are switched off',
    gateway: RecordingGateway(permissionGranted: false),
    (tester, db) async {
      expect(
        find.textContaining('Notifications are switched off'),
        findsOneWidget,
      );
      expect(find.text('Allow notifications'), findsOneWidget);
    },
  );

  appTest('a cat added through the form gets the cat catalog', (
    tester,
    db,
  ) async {
    await tester.tap(find.byKey(const Key('add-person')));
    await settle(tester);
    await tester.tap(find.text('Cat'));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('person-name')), 'Minka');
    await tester.tap(find.byKey(const Key('pick-date-of-birth')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), '07202026');
    await tester.tap(find.byKey(const Key('date-input-ok')));
    await settle(tester);

    // Rabies is a choice for a cat, where it is standard for a dog.
    await tester.dragUntilVisible(
      find.byKey(const Key('optional-cat-rabies')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.byKey(const Key('optional-dog-deworming')), findsNothing);
    await saveForm(tester);

    expect((await db.allPersons()).single.species, Species.cat);

    await tester.tap(find.text('Minka'));
    await settle(tester);
    expect(find.textContaining('Cat flu and panleukopenia'), findsWidgets);
    expect(find.text('U6'), findsNothing);
  });

  appTest(
    'a vaccination from decades ago can be recorded on its real date',
    people: [
      Person(id: 'sara', name: 'Sara', dateOfBirth: DateTime.utc(1988, 6, 30)),
    ],
    (tester, db) async {
      await tester.tap(find.text('Sara'));
      await settle(tester);
      await scrollTo(tester, find.text('Measles vaccination for adults'));
      await tester.ensureVisible(find.text('Measles vaccination for adults'));
      await settle(tester);
      await tester.tap(find.text('Measles vaccination for adults'));
      await settle(tester);

      // The second childhood dose, five years before this rule's window even
      // opens.
      await tester.tap(find.byKey(const Key('mark-done')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('date-input')), '05152001');
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await settle(tester);

      final recorded = (await db.allCompletions()).single;
      expect(recorded.ruleId, 'measles-adult');
      expect(recorded.completedOn, DateTime.utc(2001, 5, 15));
      expect(find.text('Done'), findsOneWidget);
    },
  );

  appTest(
    'a date before the person was born is refused',
    people: [
      Person(id: 'sara', name: 'Sara', dateOfBirth: DateTime.utc(1988, 6, 30)),
    ],
    (tester, db) async {
      await tester.tap(find.text('Sara'));
      await settle(tester);
      await scrollTo(tester, find.text('Measles vaccination for adults'));
      await tester.ensureVisible(find.text('Measles vaccination for adults'));
      await settle(tester);
      await tester.tap(find.text('Measles vaccination for adults'));
      await settle(tester);

      await tester.tap(find.byKey(const Key('mark-done')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('date-input')), '05151980');
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await settle(tester);

      expect(find.text('Out of range.'), findsOneWidget);
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
