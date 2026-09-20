import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/occurrence.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/domain/schedule_engine.dart';

import '../support/catalogs.dart';

void main() {
  final catalogs = CatalogSet([catalogNamed('vaccinations')]);

  // Pinned so the dates below can be checked against the calendar by hand.
  final birth = DateTime.utc(2026, 1, 15);
  final baby = Person(id: 'p1', name: 'Kind', dateOfBirth: birth);

  List<Occurrence> scheduleFor({
    Person? person,
    List<Completion> completions = const [],
    DateTime? today,
  }) => computeOccurrences(
    person: person ?? baby,
    catalogs: catalogs,
    completions: completions,
    today: today ?? birth,
  );

  Occurrence dose(
    String ruleId,
    String doseId, {
    List<Completion> done = const [],
  }) => scheduleFor(
    completions: done,
  ).firstWhere((o) => o.rule.id == ruleId && o.instanceId == doseId);

  test('the six-in-one series sits on the calendar months', () {
    expect(dose('six-in-one', 'g1').windowStart, DateTime.utc(2026, 3, 15));
    expect(dose('six-in-one', 'g2').windowStart, DateTime.utc(2026, 5, 15));
    expect(dose('six-in-one', 'g3').windowStart, DateTime.utc(2026, 12, 15));
  });

  test('a dose whose predecessor is unrecorded is provisional', () {
    // Its real earliest date depends on when the dose before it was given,
    // which nobody has entered yet.
    expect(dose('six-in-one', 'g2').provisional, isTrue);
    expect(dose('six-in-one', 'g1').provisional, isFalse);
  });

  test('a late dose pushes the one after it, not the other way round', () {
    // The second dose was given four months late. The third may not follow
    // sooner than six months after it, which is later than its age window.
    final late = [
      Completion(
        personId: 'p1',
        ruleId: 'six-in-one',
        doseId: 'g1',
        completedOn: DateTime.utc(2026, 3, 15),
      ),
      Completion(
        personId: 'p1',
        ruleId: 'six-in-one',
        doseId: 'g2',
        completedOn: DateTime.utc(2026, 9, 15),
      ),
    ];

    final third = dose('six-in-one', 'g3', done: late);
    expect(third.windowStart, DateTime.utc(2027, 3, 15));
    expect(third.provisional, isFalse);
  });

  test('an on-time dose leaves the next one on its age window', () {
    final onTime = [
      Completion(
        personId: 'p1',
        ruleId: 'six-in-one',
        doseId: 'g1',
        completedOn: DateTime.utc(2026, 3, 15),
      ),
      Completion(
        personId: 'p1',
        ruleId: 'six-in-one',
        doseId: 'g2',
        completedOn: DateTime.utc(2026, 5, 15),
      ),
    ];
    // Six months after the second dose is November, but the calendar puts the
    // third at eleven months, and the later of the two wins.
    expect(
      dose('six-in-one', 'g3', done: onTime).windowStart,
      DateTime.utc(2026, 12, 15),
    );
  });

  test('rotavirus drops off the timeline once it can no longer be given', () {
    // The series has to be finished by the 32nd week of life; after that the
    // entitlement is not late, it is gone.
    final inTime = scheduleFor(today: DateTime.utc(2026, 5, 1));
    expect(inTime.where((o) => o.rule.id == 'rotavirus'), isNotEmpty);

    final tooLate = scheduleFor(today: DateTime.utc(2026, 9, 15));
    expect(tooLate.where((o) => o.rule.id == 'rotavirus'), isEmpty);
  });

  test("an adult gets none of the infant vaccinations", () {
    final adult = Person(
      id: 'a',
      name: 'Erwachsen',
      dateOfBirth: DateTime.utc(1980, 5, 5),
    );
    final ids = scheduleFor(
      person: adult,
      today: DateTime.utc(2026, 9, 20),
    ).map((o) => o.rule.id).toSet();

    expect(ids, isNot(contains('six-in-one')));
    expect(ids, isNot(contains('rotavirus')));
    expect(ids, isNot(contains('meningococcal-b')));
    expect(ids, contains('td-booster'));
  });

  test('the tetanus booster counts ten years from the last one given', () {
    final adult = Person(
      id: 'a',
      name: 'Erwachsen',
      dateOfBirth: DateTime.utc(1980, 5, 5),
    );
    final schedule = scheduleFor(
      person: adult,
      today: DateTime.utc(2026, 9, 20),
      completions: [
        Completion(
          personId: 'a',
          ruleId: 'td-booster',
          completedOn: DateTime.utc(2021, 3, 2),
        ),
      ],
    ).where((o) => o.rule.id == 'td-booster').toList();

    expect(schedule.first.status, OccurrenceStatus.done);
    expect(
      schedule
          .where((o) => o.status != OccurrenceStatus.done)
          .first
          .windowStart,
      DateTime.utc(2031, 3, 2),
    );
  });

  test('the shingles vaccination opens at sixty, not before', () {
    final sixty = Person(
      id: 's',
      name: 'Sechzig',
      dateOfBirth: DateTime.utc(1966, 4, 1),
    );
    final first = scheduleFor(
      person: sixty,
      today: DateTime.utc(2026, 9, 20),
    ).firstWhere((o) => o.rule.id == 'herpes-zoster');

    expect(first.windowStart, DateTime.utc(2026, 4, 1));
    expect(first.status, OccurrenceStatus.due);
  });
}
