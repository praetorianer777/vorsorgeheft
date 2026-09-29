import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

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

  /// Left out where the point is what the app itself shows, so that the
  /// engine's own default is what gets tested.
  Duration? horizon,
}) => horizon == null
    ? computeOccurrences(
        person: person,
        catalogs: catalogs,
        completions: completions,
        today: today,
      )
    : computeOccurrences(
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
        catalogs: catalogOf([
          {
            'id': 'quarterly',
            'schedule': {
              'type': 'recurring',
              'from': {'years': 1},
              'every': {'months': 3},
            },
          },
        ]),
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
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

    test('changes to the later interval once a booster has been given', () {
      // TBE: three years after the series, then every five. The first
      // booster counts from the series; the one after it counts from the
      // booster before.
      final catalogs = catalogOf([
        {
          'id': 'tbe',
          'schedule': {
            'type': 'series',
            'doses': [
              {
                'id': '1',
                'from': {'years': 1},
              },
            ],
          },
        },
        {
          'id': 'tbe-booster',
          'schedule': {
            'type': 'booster',
            'after': 'tbe',
            'every': {'years': 3},
            'thenEvery': {'years': 5},
          },
        },
      ]);
      final person = personBornOn(DateTime.utc(1990, 1, 1));
      final today = DateTime.utc(2026, 9, 20);
      final series = Completion(
        personId: 'p1',
        ruleId: 'tbe',
        doseId: '1',
        completedOn: DateTime.utc(2025, 4, 3),
      );

      final afterSeries = run(
        catalogs: catalogs,
        person: person,
        today: today,
        completions: [series],
        horizon: const Duration(days: 4000),
      ).where((o) => o.rule.id == 'tbe-booster').map((o) => o.windowStart);
      // One at a time, five years apart: the second is not listed until the
      // first is recorded, which is also when its date stops being a guess.
      expect(afterSeries, [DateTime.utc(2028, 4, 3)]);

      final afterBooster = run(
        catalogs: catalogs,
        person: person,
        today: today,
        completions: [
          series,
          Completion(
            personId: 'p1',
            ruleId: 'tbe-booster',
            completedOn: DateTime.utc(2026, 6, 1),
          ),
        ],
        horizon: const Duration(days: 1),
      ).where((o) => o.rule.id == 'tbe-booster' && o.isOpen).single;
      expect(afterBooster.windowStart, DateTime.utc(2031, 6, 1));
    });
  });

  group('optional rules', () {
    final catalogs = catalogOf([
      {
        'id': 'flu',
        'optional': true,
        'schedule': {
          'type': 'recurring',
          'from': {'years': 18},
          'every': {'years': 1},
        },
      },
      {
        'id': 'tbe',
        'optional': true,
        'schedule': {
          'type': 'series',
          'doses': [
            {
              'id': '1',
              'from': {'years': 1},
            },
          ],
        },
      },
      {
        'id': 'tbe-booster',
        'optional': true,
        'schedule': {
          'type': 'booster',
          'after': 'tbe',
          'every': {'years': 3},
          'fromAge': {'years': 4},
        },
      },
      u6(),
    ]);
    final today = DateTime.utc(2026, 9, 20);
    Set<String> rulesFor(Person person) => run(
      catalogs: catalogs,
      person: person,
      today: today,
    ).map((o) => o.rule.id).toSet();

    test('stay off the timeline until switched on', () {
      expect(rulesFor(personBornOn(DateTime.utc(1990, 1, 1))), {'u6'});
    });

    test('appear once the person has switched them on', () {
      final person = Person(
        id: 'p1',
        name: 'Test',
        dateOfBirth: DateTime.utc(1990, 1, 1),
        optionalRules: const {'flu'},
      );
      expect(rulesFor(person), {'u6', 'flu'});
    });

    test('a booster follows the switch of the series it refreshes', () {
      // Nobody wants a booster for a series they never had, and nobody who
      // had the series wants a second switch for its booster.
      final person = Person(
        id: 'p1',
        name: 'Test',
        dateOfBirth: DateTime.utc(1990, 1, 1),
        optionalRules: const {'tbe'},
      );
      expect(rulesFor(person), {'u6', 'tbe', 'tbe-booster'});
    });

    test('the switches on offer are the rules, not their boosters', () {
      expect(switchableRules(catalogs).map((r) => r.id), ['flu', 'tbe']);
    });
  });

  group('seasons', () {
    /// The flu vaccination: one per winter, from October to the end of
    /// January, from the age of six months and no longer once someone is
    /// sixty and the standard rule takes over.
    final flu = catalogOf([
      {
        'id': 'flu',
        'schedule': {
          'type': 'seasonal',
          'from': {'months': 6},
          'until': {'years': 60},
          'opens': {'month': 10},
          'closes': {'month': 1},
        },
      },
    ]);
    final person = personBornOn(DateTime.utc(1990, 4, 10));

    Occurrence on(DateTime today, {List<Completion> completions = const []}) =>
        run(
          catalogs: flu,
          person: person,
          today: today,
          completions: completions,
        ).where((o) => o.isOpen).single;

    Completion had(DateTime day) =>
        Completion(personId: 'p1', ruleId: 'flu', completedOn: day);

    test('the same winter whatever month someone was born in', () {
      // Born in April, and the season still opens in October. This is the
      // whole point: a yearly interval from a birthday told this person to
      // have a flu shot in April.
      final o = on(DateTime.utc(2026, 9, 20));
      expect(o.windowStart, DateTime.utc(2026, 10, 1));
      expect(o.windowEnd, DateTime.utc(2027, 1, 31));
      expect(o.status, OccurrenceStatus.upcoming);
    });

    test('due from the day it opens to the day it closes', () {
      expect(on(DateTime.utc(2026, 10, 1)).status, OccurrenceStatus.due);
      expect(on(DateTime.utc(2026, 12, 24)).status, OccurrenceStatus.due);
      expect(on(DateTime.utc(2027, 1, 31)).status, OccurrenceStatus.due);
    });

    test('a winter that has passed gives way to the next', () {
      // Nothing carries over: a shot missed in January cannot be had in
      // February, and what can be had is next winter's.
      final o = on(DateTime.utc(2027, 2, 1));
      expect(o.windowStart, DateTime.utc(2027, 10, 1));
      expect(o.status, OccurrenceStatus.upcoming);
    });

    test('having it settles that winter and moves on to the next', () {
      final timeline = run(
        catalogs: flu,
        person: person,
        today: DateTime.utc(2026, 11, 20),
        completions: [had(DateTime.utc(2026, 11, 3))],
      );
      final done = timeline.singleWhere(
        (o) => o.status == OccurrenceStatus.done,
      );
      expect(done.instanceId, '2026');
      expect(done.completedOn, DateTime.utc(2026, 11, 3));

      final next = timeline.singleWhere((o) => o.isOpen);
      expect(next.instanceId, '2027');
      expect(next.windowStart, DateTime.utc(2027, 10, 1));
    });

    test('one had in January belongs to the winter that opened in October', () {
      final timeline = run(
        catalogs: flu,
        person: person,
        today: DateTime.utc(2027, 1, 20),
        completions: [had(DateTime.utc(2027, 1, 8))],
      );
      expect(
        timeline.singleWhere((o) => o.completedOn != null).instanceId,
        '2026',
      );
      expect(timeline.where((o) => o.isOpen).single.instanceId, '2027');
    });

    test('one winter each, however many are recorded', () {
      final timeline = run(
        catalogs: flu,
        person: person,
        today: DateTime.utc(2026, 11, 20),
        completions: [
          had(DateTime.utc(2024, 10, 30)),
          had(DateTime.utc(2025, 12, 2)),
          had(DateTime.utc(2026, 11, 3)),
        ],
      );
      expect(
        timeline.where((o) => o.completedOn != null).map((o) => o.instanceId),
        ['2024', '2025', '2026'],
      );
      expect(timeline.where((o) => o.isOpen), hasLength(1));
    });

    test('nobody is offered it before they are old enough', () {
      // Six months old in the January of the season that is running: the
      // season they can have one in is the next.
      final baby = personBornOn(DateTime.utc(2026, 8, 1));
      final o = run(
        catalogs: flu,
        person: baby,
        today: DateTime.utc(2026, 11, 1),
      ).where((o) => o.isOpen).single;
      expect(o.windowStart, DateTime.utc(2027, 10, 1));
    });

    test('and not after the age where another rule takes over', () {
      final nearlySixty = personBornOn(DateTime.utc(1967, 4, 10));
      expect(
        run(
          catalogs: flu,
          person: nearlySixty,
          today: DateTime.utc(2026, 9, 20),
        ).where((o) => o.isOpen),
        isNotEmpty,
      );
      final sixty = personBornOn(DateTime.utc(1966, 4, 10));
      expect(
        run(catalogs: flu, person: sixty, today: DateTime.utc(2026, 9, 20)),
        isEmpty,
      );
    });

    test('a season inside one year does not run over its turn', () {
      // The COVID-19 booster is an autumn, not a winter.
      final autumn = catalogOf([
        {
          'id': 'covid',
          'schedule': {
            'type': 'seasonal',
            'from': {'years': 75},
            'opens': {'month': 10},
            'closes': {'month': 11},
          },
        },
      ]);
      final old = personBornOn(DateTime.utc(1940, 3, 3));
      final o = run(
        catalogs: autumn,
        person: old,
        today: DateTime.utc(2026, 10, 15),
      ).single;
      expect(o.windowStart, DateTime.utc(2026, 10, 1));
      expect(o.windowEnd, DateTime.utc(2026, 11, 30));
      expect(o.status, OccurrenceStatus.due);

      // In December that season is over, and one had in December belongs to
      // the year it happened in rather than to the season before it.
      expect(
        run(
          catalogs: autumn,
          person: old,
          today: DateTime.utc(2026, 12, 1),
        ).single.windowStart,
        DateTime.utc(2027, 10, 1),
      );
    });
  });

  group('what the horizon cuts off', () {
    final yearly = catalogOf([
      {
        'id': 'yearly',
        'schedule': {
          'type': 'recurring',
          'from': {'years': 35},
          'every': {'years': 1},
        },
      },
    ]);

    final quarterly = catalogOf([
      {
        'id': 'quarterly',
        'schedule': {
          'type': 'recurring',
          'from': {'years': 35},
          'every': {'months': 3},
        },
      },
    ]);

    test('every repeat inside the horizon is generated, none beyond', () {
      final occurrences = run(
        catalogs: quarterly,
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 200),
      );
      expect(occurrences.map((o) => o.windowStart), [
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 12, 1),
        DateTime.utc(2027, 3, 1),
      ]);
    });

    test('by default that is the next three months of them', () {
      final occurrences = run(
        catalogs: quarterly,
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
      );
      expect(occurrences.map((o) => o.windowStart), [
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 12, 1),
      ]);
    });

    test('a yearly entitlement is listed once', () {
      final occurrences = run(
        catalogs: yearly,
        person: personBornOn(DateTime.utc(1985, 6, 1)),
        today: DateTime.utc(2026, 9, 20),
      );
      expect(occurrences.map((o) => o.windowStart), [DateTime.utc(2026, 6, 1)]);
    });

    test('still once when the next cycle starts within the horizon', () {
      // Born in November, so the cycle running now ends and the next one
      // begins six weeks from today. The horizon cannot separate those: a
      // yearly window is a year long, so its successor always opens the day
      // it closes. This is the case that kept the flu vaccination standing
      // under "needs attention" and again under "coming up".
      final occurrences = run(
        catalogs: yearly,
        person: personBornOn(DateTime.utc(1985, 11, 1)),
        today: DateTime.utc(2026, 9, 20),
      );
      expect(occurrences.map((o) => o.windowStart), [
        DateTime.utc(2025, 11, 1),
      ]);
    });

    test('however long the horizon is', () {
      expect(
        run(
          catalogs: yearly,
          person: personBornOn(DateTime.utc(1985, 6, 1)),
          today: DateTime.utc(2026, 9, 20),
          horizon: const Duration(days: 3650),
        ),
        hasLength(1),
      );
    });

    test('a booster repeats inside the horizon the same way', () {
      final occurrences = run(
        catalogs: catalogOf([
          {
            'id': 'td-booster',
            'schedule': {
              'type': 'booster',
              'every': {'years': 10},
              'fromAge': {'years': 18},
            },
          },
        ]),
        person: personBornOn(DateTime.utc(2000, 5, 5)),
        today: DateTime.utc(2026, 9, 20),
        horizon: const Duration(days: 730),
      );
      // Ten years apart, so one at a time, like any other entitlement that
      // comes round in a year or more.
      expect(occurrences.map((o) => o.windowStart), [DateTime.utc(2018, 5, 5)]);
    });

    test('a booster that comes round monthly keeps its plan', () {
      final occurrences = run(
        catalogs: catalogOf([
          {
            'id': 'tick-protection',
            'schedule': {
              'type': 'booster',
              'every': {'months': 1},
              'fromAge': {'years': 1},
            },
          },
        ]),
        person: personBornOn(DateTime.utc(2020, 5, 5)),
        today: DateTime.utc(2026, 9, 20),
      );
      expect(occurrences.length, greaterThan(2));
    });
  });

  group('history that does not fit the catalog', () {
    test('a completion for a rule no catalog knows is ignored', () {
      // A rule can be dropped from a catalog after somebody recorded it: the
      // entry stays in their history and must not break the schedule.
      final occurrences = run(
        catalogs: catalogOf([u6()]),
        person: personBornOn(birth),
        today: DateTime.utc(2026, 1, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'retired-rule',
            completedOn: DateTime.utc(2025, 12, 20),
          ),
        ],
      );
      expect(occurrences.map((o) => o.rule.id), ['u6']);
      expect(occurrences.single.status, OccurrenceStatus.due);
    });

    test('a skipped dose leaves the next one provisional', () {
      // Skipping records a decision, not a date the gap could count from.
      final occurrences = run(
        catalogs: catalogOf([
          {
            'id': 'sixfold',
            'schedule': {
              'type': 'series',
              'doses': [
                {
                  'id': '1',
                  'from': {'months': 2},
                },
                {
                  'id': '2',
                  'from': {'months': 4},
                  'minIntervalFromPrevious': {'months': 2},
                },
              ],
            },
          },
        ]),
        person: personBornOn(DateTime.utc(2026, 1, 10)),
        today: DateTime.utc(2026, 4, 1),
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'sixfold',
            doseId: '1',
            completedOn: DateTime.utc(2026, 3, 1),
            skipped: true,
          ),
        ],
      );
      final second = occurrences.firstWhere((o) => o.instanceId == '2');
      expect(second.provisional, isTrue);
      expect(second.windowStart, DateTime.utc(2026, 5, 10));
    });

    test('a booster counts from the later of its own and the primary', () {
      // The childhood series was entered years after the adult had already
      // had a booster: the shot actually given last is what the ten years
      // run from, whichever rule it was recorded under.
      final catalogs = catalogOf([
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
        {
          'id': 'td-booster',
          'schedule': {
            'type': 'booster',
            'after': 'td-primary',
            'every': {'years': 10},
          },
        },
      ]);
      Completion done(String ruleId, DateTime on, {String? doseId}) =>
          Completion(
            personId: 'p1',
            ruleId: ruleId,
            doseId: doseId,
            completedOn: on,
          );

      DateTime nextBoosterWith(List<Completion> history) => run(
        catalogs: catalogs,
        person: personBornOn(DateTime.utc(1990, 1, 1)),
        today: DateTime.utc(2026, 9, 20),
        completions: history,
        horizon: const Duration(days: 1),
      ).firstWhere((o) => o.rule.id == 'td-booster' && o.isOpen).windowStart;

      expect(
        nextBoosterWith([
          done('td-booster', DateTime.utc(2012, 6, 1)),
          done('td-primary', DateTime.utc(2015, 4, 3), doseId: '1'),
        ]),
        DateTime.utc(2025, 4, 3),
      );
      expect(
        nextBoosterWith([
          done('td-primary', DateTime.utc(2015, 4, 3), doseId: '1'),
          done('td-booster', DateTime.utc(2020, 6, 1)),
        ]),
        DateTime.utc(2030, 6, 1),
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
