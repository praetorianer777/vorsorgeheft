import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/occurrence.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/domain/schedule_engine.dart';

/// A retired rule keeps its id so that what was recorded under it stays
/// readable, and stops producing anything new from its retirement date on.
void main() {
  final birth = DateTime.utc(2020, 1, 1);
  final today = DateTime.utc(2026, 9, 20);
  final person = Person(id: 'p1', name: 'Test', dateOfBirth: birth);

  CatalogSet catalogWith(Map<String, Object?> rule) => CatalogSet([
    Catalog.fromJson({
      'catalogId': 'test',
      'catalogVersion': '2026.09',
      'name': {'en': 'Test', 'de': 'Test'},
      'sources': {
        'src': {
          'name': {'en': 'Guideline', 'de': 'Richtlinie'},
          'url': 'https://example.org/guideline',
          'asOf': '2026-09-20',
        },
      },
      'rules': [
        {
          'title': {'en': rule['id'], 'de': rule['id']},
          'description': {'en': 'desc', 'de': 'Beschreibung'},
          'source': 'src',
          ...rule,
        },
      ],
    }),
  ]);

  List<Occurrence> run(
    CatalogSet catalogs, [
    List<Completion> done = const [],
  ]) => computeOccurrences(
    person: person,
    catalogs: catalogs,
    completions: done,
    today: today,
  );

  group('a recurring rule retired mid-life', () {
    final yearly = {
      'id': 'yearly',
      'retiredOn': '2026-01-01',
      'schedule': {
        'type': 'recurring',
        'from': {'years': 3},
        'every': {'years': 1},
      },
    };

    test('plans nothing whose window starts on or after the date', () {
      expect(run(catalogWith(yearly)), isEmpty);
    });

    test('keeps what was recorded before, shown as done', () {
      final recorded = Completion(
        personId: 'p1',
        ruleId: 'yearly',
        completedOn: DateTime.utc(2024, 3, 1),
      );
      final occurrences = run(catalogWith(yearly), [recorded]);
      expect(occurrences, hasLength(1));
      expect(occurrences.single.status, OccurrenceStatus.done);
      expect(occurrences.single.completedOn, DateTime.utc(2024, 3, 1));
    });

    test('keeps what was recorded after the date, too', () {
      // A retired entitlement may still have been had, on the family's own
      // account or under a transitional rule; a recorded fact is not planned.
      final recorded = Completion(
        personId: 'p1',
        ruleId: 'yearly',
        completedOn: DateTime.utc(2026, 5, 1),
      );
      final occurrences = run(catalogWith(yearly), [recorded]);
      expect(occurrences.single.status, OccurrenceStatus.done);
    });

    test('still plans the repeat whose window opened before the date', () {
      final retiredLater = {...yearly, 'retiredOn': '2026-06-01'};
      final occurrences = run(catalogWith(retiredLater));
      expect(occurrences.single.windowStart, DateTime.utc(2026, 1, 1));
      expect(occurrences.single.status, OccurrenceStatus.due);
    });
  });

  test('a retired age window before the date is unaffected', () {
    final window = {
      'id': 'u-old',
      'retiredOn': '2030-01-01',
      'schedule': {
        'type': 'ageWindow',
        'from': {'years': 6},
        'to': {'years': 7},
      },
    };
    expect(run(catalogWith(window)).single.status, OccurrenceStatus.due);
  });

  test('a retired series keeps its recorded doses and drops the open ones', () {
    final series = {
      'id': 'shots',
      'retiredOn': '2021-01-01',
      'schedule': {
        'type': 'series',
        'doses': [
          {
            'id': 'g1',
            'from': {'months': 2},
          },
          {
            'id': 'g2',
            'from': {'months': 4},
          },
          {
            'id': 'g3',
            'from': {'years': 2},
          },
        ],
      },
    };
    final first = Completion(
      personId: 'p1',
      ruleId: 'shots',
      doseId: 'g1',
      completedOn: DateTime.utc(2020, 3, 5),
    );
    final occurrences = run(catalogWith(series), [first]);
    expect(occurrences.map((o) => o.instanceId), ['g1', 'g2']);
    expect(occurrences.first.status, OccurrenceStatus.done);
    expect(occurrences.last.status, OccurrenceStatus.due);
  });
}
