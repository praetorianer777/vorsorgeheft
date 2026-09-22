import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

/// Dogs and cats after the StIKo Vet guideline (6th edition, 2025) and the
/// ESCCAP recommendations. The expected weeks and months are the guideline's
/// own table, not read off the catalogs.
void main() {
  final catalogs = shippedCatalogs();
  final today = DateTime.utc(2026, 9, 22);

  DateTime bornWeeksAgo(int weeks) => today.subtract(Duration(days: weeks * 7));
  DateTime bornYearsAgo(int years) =>
      DateTime.utc(today.year - years, today.month, today.day);

  List<Occurrence> timelineOf(
    Species species,
    DateTime birth, {
    Set<String> optional = const {},
    List<Completion> completions = const [],
  }) => computeOccurrences(
    person: Person(
      id: 'p',
      name: 'P',
      dateOfBirth: birth,
      species: species,
      optionalRules: optional,
    ),
    catalogs: catalogs,
    completions: completions,
    today: today,
  );

  String label(Occurrence o) =>
      o.doseId == null ? o.rule.id : '${o.rule.id}#${o.doseId}';

  Set<String> open(List<Occurrence> t) => {
    for (final o in t)
      if (o.status == OccurrenceStatus.due ||
          o.status == OccurrenceStatus.overdue)
        label(o),
  };

  DateTime startOf(List<Occurrence> t, String id) =>
      t.singleWhere((o) => label(o) == id).windowStart;

  group('each species sees only its own catalogs', () {
    test('a dog never sees a check-up or vaccination for people', () {
      final rules = timelineOf(
        Species.dog,
        bornWeeksAgo(9),
      ).map((o) => o.rule.catalogId).toSet();
      expect(rules, {'dogs'});
    });

    test('a cat only sees the cat catalog', () {
      final rules = timelineOf(
        Species.cat,
        bornYearsAgo(3),
      ).map((o) => o.rule.catalogId).toSet();
      expect(rules, {'cats'});
    });

    test('a child never sees a dog or cat rule', () {
      final rules = timelineOf(
        Species.human,
        bornWeeksAgo(9),
      ).map((o) => o.rule.catalogId).toSet();
      expect(rules, isNot(contains('dogs')));
      expect(rules, isNot(contains('cats')));
    });

    test('the switches offered follow the species', () {
      final dog = switchableRules(catalogs, species: Species.dog);
      final cat = switchableRules(catalogs, species: Species.cat);
      final human = switchableRules(catalogs);
      expect(dog.map((r) => r.id), ['dog-deworming', 'dog-ectoparasites']);
      expect(cat.map((r) => r.id), [
        'cat-rabies',
        'cat-felv',
        'cat-deworming',
        'cat-ectoparasites',
      ]);
      expect(human.map((r) => r.catalogId).toSet(), {'vaccinations'});
    });
  });

  group('a puppy', () {
    test(
      'follows the StIKo Vet schedule of 8, 12 and 16 weeks and 15 months',
      () {
        final birth = bornWeeksAgo(9);
        final t = timelineOf(Species.dog, birth);
        expect(
          startOf(t, 'dog-distemper-parvo#g1'),
          birth.add(const Duration(days: 56)),
        );
        expect(
          startOf(t, 'dog-distemper-parvo#g2'),
          birth.add(const Duration(days: 84)),
        );
        expect(
          startOf(t, 'dog-distemper-parvo#g3'),
          birth.add(const Duration(days: 112)),
        );
        expect(
          startOf(t, 'dog-distemper-parvo#g4'),
          DateTime.utc(birth.year, birth.month + 15, birth.day),
        );
        // Leptospirosis is given at 8 and 12 weeks and 15 months, not at 16.
        expect(t.where((o) => o.rule.id == 'dog-leptospirosis').map(label), [
          'dog-leptospirosis#g1',
          'dog-leptospirosis#g2',
          'dog-leptospirosis#g3',
        ]);
        expect(
          startOf(t, 'dog-rabies#g1'),
          birth.add(const Duration(days: 84)),
        );
      },
    );

    test('at nine weeks has the first core doses open, rabies not yet', () {
      final t = timelineOf(Species.dog, bornWeeksAgo(9));
      expect(open(t), {'dog-distemper-parvo#g1', 'dog-leptospirosis#g1'});
    });

    test('at thirteen weeks rabies is due as standard', () {
      final t = timelineOf(Species.dog, bornWeeksAgo(13));
      expect(open(t), contains('dog-rabies#g1'));
    });

    test('has no deworming or tick protection until switched on', () {
      final t = timelineOf(Species.dog, bornWeeksAgo(3));
      expect(t.map((o) => o.rule.id), isNot(contains('dog-deworming')));
      expect(t.map((o) => o.rule.id), isNot(contains('dog-ectoparasites')));
    });

    test('with deworming on, starts at two weeks, every two weeks', () {
      final birth = bornWeeksAgo(3);
      final t = timelineOf(Species.dog, birth, optional: {'dog-deworming'});
      expect(
        [for (var i = 1; i <= 5; i++) startOf(t, 'dog-deworming#g$i')],
        [
          for (final weeks in [2, 4, 6, 8, 10])
            birth.add(Duration(days: weeks * 7)),
        ],
      );
      expect(open(t), contains('dog-deworming#g1'));
    });
  });

  group('an adult dog entered without records', () {
    final t = timelineOf(Species.dog, bornYearsAgo(5));

    test('no longer sees the puppy series', () {
      expect(
        t.map((o) => o.rule.id),
        isNot(anyOf(contains('dog-distemper-parvo'), contains('dog-rabies'))),
      );
    });

    test('sees the boosters as due', () {
      expect(
        open(t),
        containsAll([
          'dog-distemper-parvo-booster',
          'dog-leptospirosis-booster',
          'dog-rabies-booster',
        ]),
      );
    });

    test('with deworming on, is reminded every three months', () {
      final wormed = timelineOf(
        Species.dog,
        bornYearsAgo(5),
        optional: {'dog-deworming'},
      );
      final routine = wormed
          .where((o) => o.rule.id == 'dog-deworming-routine')
          .map((o) => o.windowStart)
          .toList();
      expect(routine, hasLength(greaterThan(1)));
      expect(
        routine[1],
        DateTime.utc(routine[0].year, routine[0].month + 3, routine[0].day),
      );
    });
  });

  group('boosters count from the last dose actually given', () {
    test(
      'leptospirosis yearly, distemper and parvovirus every three years',
      () {
        final birth = bornYearsAgo(2);
        final lastDose = DateTime.utc(2025, 12, 1);
        final t = timelineOf(
          Species.dog,
          birth,
          completions: [
            for (final rule in ['dog-distemper-parvo', 'dog-leptospirosis'])
              Completion(
                personId: 'p',
                ruleId: rule,
                doseId: rule == 'dog-leptospirosis' ? 'g3' : 'g4',
                completedOn: lastDose,
              ),
          ],
        );
        expect(
          t
              .firstWhere((o) => o.rule.id == 'dog-leptospirosis-booster')
              .windowStart,
          DateTime.utc(2026, 12, 1),
        );
        expect(
          t
              .firstWhere((o) => o.rule.id == 'dog-distemper-parvo-booster')
              .windowStart,
          DateTime.utc(2028, 12, 1),
        );
      },
    );
  });

  group('a kitten', () {
    test('gets cat flu and panleukopenia at 8, 12, 16 weeks and 15 months', () {
      final birth = bornWeeksAgo(9);
      final t = timelineOf(Species.cat, birth);
      expect(startOf(t, 'cat-core#g1'), birth.add(const Duration(days: 56)));
      expect(startOf(t, 'cat-core#g3'), birth.add(const Duration(days: 112)));
      expect(open(t), {'cat-core#g1'});
    });

    test('has rabies and leukaemia only when switched on', () {
      final plain = timelineOf(Species.cat, bornWeeksAgo(13));
      expect(plain.map((o) => o.rule.id), isNot(contains('cat-rabies')));
      expect(plain.map((o) => o.rule.id), isNot(contains('cat-felv')));

      final outdoor = timelineOf(
        Species.cat,
        bornWeeksAgo(13),
        optional: {'cat-rabies', 'cat-felv'},
      );
      expect(open(outdoor), containsAll(['cat-rabies#g1', 'cat-felv#g1']));
    });

    test('with deworming on, starts at three weeks', () {
      final birth = bornWeeksAgo(4);
      final t = timelineOf(Species.cat, birth, optional: {'cat-deworming'});
      expect(
        startOf(t, 'cat-deworming#g1'),
        birth.add(const Duration(days: 21)),
      );
      expect(
        startOf(t, 'cat-deworming#g2'),
        birth.add(const Duration(days: 35)),
      );
    });
  });

  test('an adult cat without records sees the core booster as due', () {
    expect(
      open(timelineOf(Species.cat, bornYearsAgo(6))),
      contains('cat-core-booster'),
    );
  });

  test('tick protection, once switched on, comes monthly', () {
    final t = timelineOf(
      Species.cat,
      bornYearsAgo(2),
      optional: {'cat-ectoparasites'},
    );
    final ticks = t
        .where((o) => o.rule.id == 'cat-ectoparasites')
        .map((o) => o.windowStart)
        .toList();
    expect(
      ticks[1],
      DateTime.utc(ticks[0].year, ticks[0].month + 1, ticks[0].day),
    );
  });

  test('a catalog naming an unknown species is rejected', () {
    expect(
      () => Catalog.fromJson({
        'catalogId': 'horses',
        'catalogVersion': '1',
        'name': {'en': 'Horses', 'de': 'Pferde'},
        'species': ['horse'],
        'sources': {
          's': {
            'name': {'en': 'S', 'de': 'S'},
            'url': 'https://example.org',
            'asOf': '2026-01-01',
          },
        },
        'rules': [
          {
            'id': 'r',
            'title': {'en': 'R', 'de': 'R'},
            'description': {'en': 'R', 'de': 'R'},
            'source': 's',
            'schedule': {
              'type': 'recurring',
              'from': {'years': 1},
              'every': {'years': 1},
            },
          },
        ],
      }),
      throwsA(isA<CatalogFormatException>()),
    );
  });
}
