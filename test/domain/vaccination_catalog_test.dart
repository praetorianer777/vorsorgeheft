import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

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

  group('optional vaccinations', () {
    final adult = Person(
      id: 'a',
      name: 'Erwachsen',
      dateOfBirth: DateTime.utc(1990, 5, 5),
      sex: Sex.female,
    );
    final today = DateTime.utc(2026, 9, 20);

    test('are the indication vaccinations, each with a switch', () {
      expect(catalogs.rules.where((r) => r.optional).map((r) => r.id).toSet(), {
        'influenza-under-60',
        'covid-under-75',
        'tbe',
        'tbe-booster',
        'pertussis-pregnancy',
        'hpv-catch-up',
        'meningococcal-b-catch-up',
      });
      expect(switchableRules(catalogs).map((r) => r.id), [
        'influenza-under-60',
        'covid-under-75',
        'tbe',
        'pertussis-pregnancy',
        'hpv-catch-up',
        'meningococcal-b-catch-up',
      ]);
    });

    test('an adult under sixty sees no flu vaccination unless asked', () {
      final ids = scheduleFor(
        person: adult,
        today: today,
      ).map((o) => o.rule.id).toSet();
      expect(ids, isNot(contains('influenza-under-60')));
    });

    test('the flu vaccination under sixty runs yearly until sixty', () {
      final flu = scheduleFor(
        person: Person(
          id: 'a',
          name: 'Erwachsen',
          dateOfBirth: adult.dateOfBirth,
          optionalRules: const {'influenza-under-60'},
        ),
        today: today,
      ).where((o) => o.rule.id == 'influenza-under-60').toList();
      // Yearly from six months of age, so the season running now started
      // on the birthday-plus-six-months before today.
      expect(flu.first.windowStart, DateTime.utc(2025, 11, 5));
      expect(flu.first.status, OccurrenceStatus.due);
      expect(flu.first.rule.statutory, isFalse);

      // At sixty the standard rule takes over; the switch adds nothing.
      final sixty = scheduleFor(
        person: Person(
          id: 's',
          name: 'Sechzig',
          dateOfBirth: DateTime.utc(1966, 4, 1),
          optionalRules: const {'influenza-under-60'},
        ),
        today: today,
      ).map((o) => o.rule.id).toSet();
      expect(sixty, contains('influenza'));
      expect(sixty, isNot(contains('influenza-under-60')));
    });

    test('the TBE switch brings the booster with it', () {
      // The booster counts from the last dose of the series, not the first.
      final tbe = scheduleFor(
        person: Person(
          id: 'a',
          name: 'Erwachsen',
          dateOfBirth: adult.dateOfBirth,
          optionalRules: const {'tbe'},
        ),
        today: today,
        completions: [
          for (final (dose, on) in [
            ('g1', DateTime.utc(2024, 3, 1)),
            ('g2', DateTime.utc(2024, 4, 15)),
            ('g3', DateTime.utc(2025, 1, 10)),
          ])
            Completion(
              personId: 'a',
              ruleId: 'tbe',
              doseId: dose,
              completedOn: on,
            ),
        ],
      );
      final boosters = tbe
          .where((o) => o.rule.id == 'tbe-booster')
          .map((o) => o.windowStart)
          .toList();
      expect(boosters, [DateTime.utc(2028, 1, 10)]);
    });

    test('the pregnancy pertussis dose is offered to women only', () {
      final male = Person(
        id: 'm',
        name: 'Mann',
        dateOfBirth: adult.dateOfBirth,
        sex: Sex.male,
        optionalRules: const {'pertussis-pregnancy'},
      );
      expect(
        scheduleFor(person: male, today: today).map((o) => o.rule.id),
        isNot(contains('pertussis-pregnancy')),
      );
      final female = Person(
        id: 'f',
        name: 'Frau',
        dateOfBirth: adult.dateOfBirth,
        sex: Sex.female,
        optionalRules: const {'pertussis-pregnancy'},
      );
      expect(
        scheduleFor(person: female, today: today).map((o) => o.rule.id),
        contains('pertussis-pregnancy'),
      );
    });
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
