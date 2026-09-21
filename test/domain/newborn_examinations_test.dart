import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/newborn_examinations.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

void main() {
  final catalogs = CatalogSet([childrenCatalog()]);
  final mila = Person(
    id: 'infant',
    name: 'Mila',
    dateOfBirth: DateTime.utc(2026, 9, 1),
  );

  List<Occurrence> timeline(
    DateTime today, [
    List<Completion> done = const [],
  ]) => computeOccurrences(
    person: mila,
    catalogs: catalogs,
    completions: done,
    today: today,
  );

  test('nothing to offer on the day of birth', () {
    expect(unrecordedNewbornExaminations(timeline(mila.dateOfBirth)), isEmpty);
  });

  test('three weeks in, every clinic examination is on offer', () {
    final ids = unrecordedNewbornExaminations(
      timeline(DateTime.utc(2026, 9, 20)),
    ).map((o) => o.rule.id).toSet();
    expect(ids, newbornExaminationIds);
  });

  test('what was recorded is not offered again', () {
    final ids = unrecordedNewbornExaminations(
      timeline(DateTime.utc(2026, 9, 20), [
        Completion(
          personId: 'infant',
          ruleId: 'u1',
          completedOn: DateTime.utc(2026, 9, 1),
        ),
      ]),
    ).map((o) => o.rule.id);
    expect(ids, isNot(contains('u1')));
    expect(ids, contains('hearing-screening'));
  });

  test(
    'the screenings bounded by the U2 lapse rather than staying overdue',
    () {
      final byRule = {
        for (final o in timeline(DateTime.utc(2026, 10, 15)))
          o.rule.id: o.status,
      };
      expect(byRule['hearing-screening'], OccurrenceStatus.expired);
      expect(byRule['pulse-oximetry'], OccurrenceStatus.expired);
      expect(byRule['cf-screening'], OccurrenceStatus.expired);
      // The guideline names no bound for these two, so the app invents none.
      expect(byRule['u1'], OccurrenceStatus.overdue);
      expect(byRule['newborn-screening'], OccurrenceStatus.overdue);
    },
  );
}
