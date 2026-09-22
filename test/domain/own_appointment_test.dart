import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/own_appointment.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

void main() {
  final today = DateTime.utc(2026, 9, 22);
  final sara = Person(
    id: 'sara',
    name: 'Sara',
    dateOfBirth: DateTime.utc(1988, 6, 30),
  );
  final eyes = OwnAppointment(
    id: 'eyes',
    personId: 'sara',
    title: 'Eye check',
    firstOn: DateTime.utc(2026, 11, 3),
    everyMonths: 12,
    note: 'Dr. Weber, bring the glasses',
  );

  List<Occurrence> own({
    List<Completion> completions = const [],
    DateTime? on,
    List<OwnAppointment> appointments = const [],
  }) => computeOccurrences(
    person: sara,
    catalogs: CatalogSet([childrenCatalog()]),
    completions: completions,
    ownAppointments: appointments,
    today: on ?? today,
  ).where((o) => o.rule.own).toList();

  test('an own appointment is scheduled from its first date', () {
    final occurrences = own(appointments: [eyes]);
    // Repeats within the horizon follow, like any recurring entitlement.
    expect(occurrences.map((o) => o.windowStart), [
      DateTime.utc(2026, 11, 3),
      DateTime.utc(2027, 11, 3),
    ]);
    final first = occurrences.first;
    expect(first.rule.id, 'own:eyes');
    expect(first.windowStart, DateTime.utc(2026, 11, 3));
    expect(first.windowEnd, DateTime.utc(2027, 11, 3));
    expect(first.status, OccurrenceStatus.upcoming);
    expect(first.rule.title('de'), 'Eye check');
    expect(first.rule.description('en'), 'Dr. Weber, bring the glasses');
  });

  test('the next one counts from the day it was actually done', () {
    final occurrences = own(
      appointments: [eyes],
      completions: [
        Completion(
          personId: 'sara',
          ruleId: 'own:eyes',
          completedOn: DateTime.utc(2026, 12, 1),
        ),
      ],
      on: DateTime.utc(2027, 1, 1),
    );
    expect(occurrences.first.status, OccurrenceStatus.done);
    expect(occurrences.first.windowStart, DateTime.utc(2026, 12, 1));
    expect(occurrences[1].status, OccurrenceStatus.upcoming);
    expect(occurrences[1].windowStart, DateTime.utc(2027, 12, 1));
  });

  test('a first date in the past is due now, not overdue since then', () {
    final first = own(
      appointments: [eyes.copyWith(firstOn: DateTime.utc(2020, 3, 1))],
    ).first;
    expect(first.windowStart, DateTime.utc(2026, 3, 1));
    expect(first.status, OccurrenceStatus.due);
  });

  test('someone else\'s appointment stays off the timeline', () {
    final other = OwnAppointment(
      id: 'x',
      personId: 'tom',
      title: 'Physio',
      firstOn: today,
      everyMonths: 3,
    );
    expect(own(appointments: [other]), isEmpty);
  });

  test('without a note the description repeats the title', () {
    final rule = eyes.copyWith(note: () => null).toRule();
    expect(rule.description('en'), 'Eye check');
    expect(rule.own, isTrue);
    expect(OwnAppointment.isOwnRule(rule.id), isTrue);
    expect(OwnAppointment.isOwnRule('u6'), isFalse);
  });
}
