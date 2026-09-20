import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/occurrence.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/domain/schedule_engine.dart';

const _sources = {
  'src': {
    'name': {'en': 'Guideline', 'de': 'Richtlinie'},
    'url': 'https://example.org/guideline',
    'asOf': '2026-09-20',
  },
};

CatalogSet catalogOf(List<Map<String, Object?>> rules) => CatalogSet([
  Catalog.fromJson({
    'catalogId': 'test',
    'catalogVersion': '2026.09',
    'name': {'en': 'Test', 'de': 'Test'},
    'sources': _sources,
    'rules': [
      for (final rule in rules)
        {
          'title': {'en': rule['id'], 'de': rule['id']},
          'description': {'en': 'desc', 'de': 'Beschreibung'},
          'source': 'src',
          ...rule,
        },
    ],
  }),
]);

Person personBornOn(
  DateTime birth, {
  Sex sex = Sex.notStated,
  String id = 'p1',
}) => Person(id: id, name: 'Test', dateOfBirth: birth, sex: sex);

List<Occurrence> run({
  required CatalogSet catalogs,
  required Person person,
  required DateTime today,
  List<Completion> completions = const [],
  Duration horizon = const Duration(days: 730),
}) => computeOccurrences(
  person: person,
  catalogs: catalogs,
  completions: completions,
  today: today,
  horizon: horizon,
);

Map<String, Object?> u6({bool hardDeadline = true}) => {
  'id': 'u6',
  'schedule': {
    'type': 'ageWindow',
    'from': {'months': 9},
    'to': {'months': 12},
    'toleranceTo': {'months': 14},
    'hardDeadline': hardDeadline,
  },
};

void main() {
  final birth = DateTime.utc(2025, 3, 10);

  group('age windows', () {
    final catalogs = catalogOf([u6()]);

    test('is upcoming before the window opens', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2025, 11, 1),
      ).single;
      expect(o.status, OccurrenceStatus.upcoming);
      expect(o.windowStart, DateTime.utc(2025, 12, 10));
      expect(o.deadline, DateTime.utc(2026, 5, 10));
    });

    test('is due on the first day of the window', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2025, 12, 10),
      ).single;
      expect(o.status, OccurrenceStatus.due);
    });

    test('is still due on the last day of the recommended window', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2026, 3, 10),
      ).single;
      expect(o.status, OccurrenceStatus.due);
    });

    test('is overdue between the window and the tolerance limit', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2026, 3, 11),
      ).single;
      expect(o.status, OccurrenceStatus.overdue);
    });

    test('is still catchable on the tolerance limit itself', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2026, 5, 10),
      ).single;
      expect(o.status, OccurrenceStatus.overdue);
    });

    test('expires the day after the tolerance limit', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2026, 5, 11),
      ).single;
      expect(o.status, OccurrenceStatus.expired);
    });

    test('is overdue rather than expired without a hard deadline', () {
      final o = run(
        catalogs: catalogOf([u6(hardDeadline: false)]),
        person: personBornOn(birth),
        today: DateTime.utc(2026, 5, 11),
      ).single;
      expect(o.status, OccurrenceStatus.overdue);
    });

    test('a recorded completion outranks an expired deadline', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2027, 1, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'u6',
            completedOn: DateTime.utc(2026, 1, 5),
          ),
        ],
      ).single;
      expect(o.status, OccurrenceStatus.done);
      expect(o.completedOn, DateTime.utc(2026, 1, 5));
    });

    test('a deliberate skip is distinguished from being done', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2026, 1, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'u6',
            completedOn: DateTime.utc(2025, 12, 20),
            skipped: true,
          ),
        ],
      ).single;
      expect(o.status, OccurrenceStatus.skipped);
    });

    test('another person’s completion does not settle this one', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(birth),
        today: DateTime.utc(2026, 1, 1),
        completions: [
          Completion(
            personId: 'someone-else',
            ruleId: 'u6',
            completedOn: DateTime.utc(2025, 12, 20),
          ),
        ],
      ).single;
      expect(o.status, OccurrenceStatus.due);
    });

    test('a child born today already has the whole schedule ahead', () {
      final today = DateTime.utc(2026, 9, 20);
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(today),
        today: today,
      );
      expect(occurrences, hasLength(1));
      expect(occurrences.single.status, OccurrenceStatus.upcoming);
      expect(occurrences.single.windowStart, DateTime.utc(2027, 6, 20));
    });

    test('a leap-day birthday keeps its window in a common year', () {
      final o = run(
        catalogs: catalogOf([
          {
            'id': 'four',
            'schedule': {
              'type': 'ageWindow',
              'from': {'years': 1},
              'to': {'years': 2},
            },
          },
        ]),
        person: personBornOn(DateTime.utc(2024, 2, 29)),
        today: DateTime.utc(2025, 3, 1),
      ).single;
      expect(o.windowStart, DateTime.utc(2025, 2, 28));
      expect(o.status, OccurrenceStatus.due);
    });
  });

  group('eligibility', () {
    final catalogs = catalogOf([
      {
        'id': 'mammography',
        'eligibility': {'sex': 'female'},
        'schedule': {
          'type': 'recurring',
          'from': {'years': 50},
          'every': {'years': 2},
          'until': {'years': 75},
        },
      },
    ]);
    final fifty = DateTime.utc(1970, 1, 1);
    final today = DateTime.utc(2026, 9, 20);

    test('applies definitely to the sex it names', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(fifty, sex: Sex.female),
        today: today,
      ).first;
      expect(o.applicability, Applicability.definite);
    });

    test('does not apply to the other sex at all', () {
      expect(
        run(
          catalogs: catalogs,
          person: personBornOn(fifty, sex: Sex.male),
          today: today,
        ),
        isEmpty,
      );
    });

    test('is shown as merely possible when sex is not stated', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(fifty),
        today: today,
      ).first;
      expect(o.applicability, Applicability.possible);
    });

    test('an age ceiling drops occurrences beyond it', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1949, 1, 1), sex: Sex.female),
        today: today,
        horizon: const Duration(days: 3650),
      );
      for (final o in occurrences) {
        expect(o.windowStart.isBefore(DateTime.utc(2025, 1, 2)), isTrue);
      }
    });

    test('someone too old for every rule gets an empty schedule', () {
      expect(
        run(
          catalogs: catalogOf([
            {
              'id': 'child-only',
              'eligibility': {
                'maxAge': {'years': 18},
              },
              'schedule': {
                'type': 'ageWindow',
                'from': {'years': 5},
                'to': {'years': 6},
              },
            },
          ]),
          person: personBornOn(DateTime.utc(1960, 1, 1)),
          today: today,
        ),
        isEmpty,
      );
    });
  });

  group('recurring entitlements', () {
    final catalogs = catalogOf([
      {
        'id': 'checkup',
        'schedule': {
          'type': 'recurring',
          'from': {'years': 35},
          'every': {'years': 3},
        },
      },
    ]);

    test('the next one is generated even beyond the horizon', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(2000, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 365),
      );
      expect(occurrences, hasLength(1));
      expect(occurrences.single.windowStart, DateTime.utc(2035, 6, 1));
      expect(occurrences.single.status, OccurrenceStatus.upcoming);
    });

    test('the interval counts from the last one actually taken', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'checkup',
            completedOn: DateTime.utc(2025, 2, 10),
          ),
        ],
        horizon: const Duration(days: 1),
      );
      final done = occurrences.where((o) => o.status == OccurrenceStatus.done);
      expect(done, hasLength(1));
      final next = occurrences.firstWhere((o) => o.isOpen);
      expect(next.windowStart, DateTime.utc(2028, 2, 10));
    });

    test('a deliberate skip does not restart the interval', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'checkup',
            completedOn: DateTime.utc(2025, 2, 10),
            skipped: true,
          ),
        ],
        horizon: const Duration(days: 1),
      );
      final next = occurrences.firstWhere((o) => o.isOpen);
      // Three years after the skip would be 2028. The interval still runs off
      // the original grid, so the one running now is the 2026 repeat.
      expect(next.windowStart, DateTime.utc(2026, 6, 1));
      expect(next.windowStart, isNot(DateTime.utc(2028, 2, 10)));
    });

    test('only the repeat that is running is generated', () {
      // Somebody who turned 35 twenty years ago and recorded nothing has one
      // check-up they can still have: this one. Listing every missed repeat
      // since would bury it under appointments nobody can make any more.
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1970, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 1),
      );
      expect(occurrences.first.windowStart, DateTime.utc(2026, 6, 1));
      expect(occurrences.first.status, OccurrenceStatus.due);
    });

    test('repeats of one rule get distinct keys', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 2000),
      );
      final keys = occurrences.map((o) => o.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys.length, greaterThan(1));
    });

    test('an until age stops the series', () {
      final occurrences = run(
        catalogs: catalogOf([
          {
            'id': 'mammo',
            'schedule': {
              'type': 'recurring',
              'from': {'years': 50},
              'every': {'years': 2},
              'until': {'years': 75},
            },
          },
        ]),
        person: personBornOn(DateTime.utc(1950, 1, 1)),
        today: DateTime.utc(2024, 6, 1),
        horizon: const Duration(days: 3650),
      );
      expect(occurrences, hasLength(1));
      expect(occurrences.last.windowStart, DateTime.utc(2024, 1, 1));
    });

    test('a capped series that has fully elapsed leaves nothing behind', () {
      // The last two-yearly screening this person could have had ran until
      // January 2026. After that it is not overdue, it is gone.
      final occurrences = run(
        catalogs: catalogOf([
          {
            'id': 'mammo',
            'schedule': {
              'type': 'recurring',
              'from': {'years': 50},
              'every': {'years': 2},
              'until': {'years': 75},
            },
          },
        ]),
        person: personBornOn(DateTime.utc(1950, 1, 1)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 3650),
      );
      expect(occurrences, isEmpty);
    });
  });

  group('one-off entitlements', () {
    final catalogs = catalogOf([
      {
        'id': 'hepatitis',
        'schedule': {
          'type': 'onceFromAge',
          'from': {'years': 35},
        },
      },
    ]);

    test('stays due indefinitely once it opens', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1960, 1, 1)),
        today: DateTime.utc(2026, 9, 20),
      ).single;
      expect(o.windowEnd, isNull);
      expect(o.status, OccurrenceStatus.due);
    });

    test('is upcoming before the age is reached', () {
      final o = run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(2000, 1, 1)),
        today: DateTime.utc(2026, 9, 20),
      ).single;
      expect(o.status, OccurrenceStatus.upcoming);
    });
  });

  group('vaccination series', () {
    final catalogs = catalogOf([
      {
        'id': 'sixfold',
        'schedule': {
          'type': 'series',
          'doses': [
            {
              'id': '1',
              'from': {'months': 2},
              'to': {'months': 3},
            },
            {
              'id': '2',
              'from': {'months': 4},
              'minIntervalFromPrevious': {'months': 2},
            },
            {
              'id': '3',
              'from': {'months': 11},
              'minIntervalFromPrevious': {'months': 6},
            },
          ],
        },
      },
    ]);
    final infant = DateTime.utc(2026, 1, 10);

    test('one occurrence per dose, each with its own key', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(infant),
        today: DateTime.utc(2026, 2, 1),
      );
      expect(occurrences, hasLength(3));
      expect(
        occurrences.map((o) => o.instanceId),
        containsAll(<String>['1', '2', '3']),
      );
      expect(occurrences.map((o) => o.key).toSet(), hasLength(3));
    });

    test('derives from age alone while the previous dose is unrecorded', () {
      final second = run(
        catalogs: catalogs,
        person: personBornOn(infant),
        today: DateTime.utc(2026, 2, 1),
      ).firstWhere((o) => o.instanceId == '2');
      expect(second.windowStart, DateTime.utc(2026, 5, 10));
      expect(second.provisional, isTrue);
    });

    test('a late first dose pushes the second out by the minimum gap', () {
      final second = run(
        catalogs: catalogs,
        person: personBornOn(infant),
        today: DateTime.utc(2026, 7, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'sixfold',
            doseId: '1',
            completedOn: DateTime.utc(2026, 6, 20),
          ),
        ],
      ).firstWhere((o) => o.instanceId == '2');
      expect(second.windowStart, DateTime.utc(2026, 8, 20));
      expect(second.provisional, isFalse);
    });

    test('an early first dose does not pull the second before its age', () {
      final second = run(
        catalogs: catalogs,
        person: personBornOn(infant),
        today: DateTime.utc(2026, 4, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'sixfold',
            doseId: '1',
            completedOn: DateTime.utc(2026, 3, 1),
          ),
        ],
      ).firstWhere((o) => o.instanceId == '2');
      expect(second.windowStart, DateTime.utc(2026, 5, 10));
    });

    test('recording a dose settles only that dose', () {
      final occurrences = run(
        catalogs: catalogs,
        person: personBornOn(infant),
        today: DateTime.utc(2026, 4, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'sixfold',
            doseId: '1',
            completedOn: DateTime.utc(2026, 3, 1),
          ),
        ],
      );
      expect(
        occurrences.firstWhere((o) => o.instanceId == '1').status,
        OccurrenceStatus.done,
      );
      expect(
        occurrences.firstWhere((o) => o.instanceId == '2').status,
        OccurrenceStatus.upcoming,
      );
    });
  });

  group('boosters', () {
    Map<String, Object?> booster(Map<String, Object?> schedule) => {
      'id': 'td-booster',
      'schedule': {'type': 'booster', ...schedule},
    };

    test('counts ten years from the last dose of the primary series', () {
      final occurrences = run(
        catalogs: catalogOf([
          {
            'id': 'td-primary',
            'schedule': {
              'type': 'series',
              'doses': [
                {
                  'id': '1',
                  'from': {'years': 5},
                },
              ],
            },
          },
          booster({
            'after': 'td-primary',
            'every': {'years': 10},
          }),
        ]),
        person: personBornOn(DateTime.utc(2010, 1, 1)),
        today: DateTime.utc(2026, 9, 20),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'td-primary',
            doseId: '1',
            completedOn: DateTime.utc(2015, 4, 3),
          ),
        ],
        horizon: const Duration(days: 1),
      );
      final next = occurrences.firstWhere((o) => o.rule.id == 'td-booster');
      expect(next.windowStart, DateTime.utc(2025, 4, 3));
      expect(next.status, OccurrenceStatus.due);
    });

    test('falls back to an age when nothing is recorded', () {
      final o = run(
        catalogs: catalogOf([
          booster({
            'every': {'years': 10},
            'fromAge': {'years': 18},
          }),
        ]),
        person: personBornOn(DateTime.utc(2000, 5, 5)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 1),
      ).first;
      expect(o.windowStart, DateTime.utc(2018, 5, 5));
      expect(o.status, OccurrenceStatus.due);
    });

    test('produces nothing rather than guessing without either', () {
      expect(
        run(
          catalogs: catalogOf([
            booster({
              'every': {'years': 10},
            }),
          ]),
          person: personBornOn(DateTime.utc(2000, 5, 5)),
          today: DateTime.utc(2026, 9, 20),
        ),
        isEmpty,
      );
    });
  });

  test('occurrences come back in due order', () {
    final occurrences = run(
      catalogs: catalogOf([
        {
          'id': 'later',
          'schedule': {
            'type': 'ageWindow',
            'from': {'years': 5},
            'to': {'years': 6},
          },
        },
        {
          'id': 'earlier',
          'schedule': {
            'type': 'ageWindow',
            'from': {'months': 2},
            'to': {'months': 3},
          },
        },
      ]),
      person: personBornOn(DateTime.utc(2026, 1, 1)),
      today: DateTime.utc(2026, 9, 20),
    );
    expect(occurrences.map((o) => o.rule.id), ['earlier', 'later']);
  });
}
