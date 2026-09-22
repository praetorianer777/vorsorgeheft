import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/own_appointment.dart';
import 'package:vorsorgeheft/domain/person.dart';

import '../support/harness.dart';

void main() {
  final sara = Person(
    id: 'sara',
    name: 'Sara',
    dateOfBirth: DateTime.utc(1988, 6, 30),
  );

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.text('Sara'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('edit-person')));
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.dragUntilVisible(
      find.byKey(key),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await settle(tester);
  }

  Future<void> saveForm(WidgetTester tester) async {
    await reveal(tester, const Key('save-person'));
    await tester.tap(find.byKey(const Key('save-person')));
    await settle(tester);
  }

  appTest('an own appointment is added, listed and recorded', people: [sara], (
    tester,
    db,
  ) async {
    await openForm(tester);
    await reveal(tester, const Key('add-own-appointment'));
    await tester.tap(find.byKey(const Key('add-own-appointment')));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('own-title')), 'Eye check');
    await tester.tap(find.byKey(const Key('own-first-on')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), '11032026');
    await tester.tap(find.byKey(const Key('date-input-ok')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('own-every')), '2');
    await tester.tap(find.byKey(const Key('own-save')));
    await settle(tester);

    expect(find.text('Eye check'), findsOneWidget);
    expect(find.textContaining('every 2 years'), findsOneWidget);
    expect(await db.allOwnAppointments(), isEmpty);

    await saveForm(tester);
    final stored = (await db.allOwnAppointments()).single;
    expect(stored.title, 'Eye check');
    expect(stored.everyMonths, 24);
    expect(stored.firstOn, DateTime.utc(2026, 11, 3));

    await scrollTo(tester, find.text('Eye check'));
    await tester.tap(find.text('Eye check'));
    await settle(tester);
    expect(find.text('Own appointment'), findsOneWidget);
    expect(find.text('Open source'), findsNothing);

    await tester.tap(find.byKey(const Key('mark-done')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), '09152026');
    await tester.tap(find.byKey(const Key('date-input-ok')));
    await settle(tester);
    expect(find.text('Done'), findsOneWidget);
    expect((await db.allCompletions()).single.ruleId, 'own:${stored.id}');
  });

  appTest(
    'removing an own appointment takes it off the timeline',
    people: [sara],
    ownAppointments: [
      OwnAppointment(
        id: 'physio',
        personId: 'sara',
        title: 'Physio',
        firstOn: DateTime.utc(2026, 10, 1),
        everyMonths: 3,
      ),
    ],
    (tester, db) async {
      await tester.tap(find.text('Sara'));
      await settle(tester);
      await scrollTo(tester, find.text('Physio'));
      expect(find.text('Physio'), findsWidgets);

      await tester.tap(find.byKey(const Key('edit-person')));
      await settle(tester);
      await reveal(tester, const Key('own-remove-physio'));
      await tester.tap(find.byKey(const Key('own-remove-physio')));
      await settle(tester);
      await saveForm(tester);

      expect(await db.allOwnAppointments(), isEmpty);
      expect(find.text('Physio'), findsNothing);
    },
  );
}
