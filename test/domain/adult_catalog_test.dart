import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/occurrence.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/domain/schedule_engine.dart';

import '../support/catalogs.dart';

void main() {
  final catalogs = CatalogSet([catalogNamed('adults')]);
  final today = DateTime.utc(2026, 9, 20);

  Person person(Sex sex, DateTime birth) =>
      Person(id: sex.name, name: sex.name, dateOfBirth: birth, sex: sex);

  List<Occurrence> scheduleFor(
    Person p, {
    List<Completion> completions = const [],
  }) => computeOccurrences(
    person: p,
    catalogs: catalogs,
    completions: completions,
    today: today,
  );

  Set<String> ruleIdsFor(Person p) =>
      scheduleFor(p).map((o) => o.rule.id).toSet();

  final fiftyTwo = DateTime.utc(1974, 3, 3);

  test('a woman gets the screenings meant for women and not the others', () {
    final ids = ruleIdsFor(person(Sex.female, fiftyTwo));
    expect(
      ids,
      containsAll(['mammography', 'cervical-cotest', 'gynaecological-exam']),
    );
    expect(ids, isNot(contains('prostate-exam')));
    expect(ids, isNot(contains('aortic-aneurysm')));
  });

  test('a man gets the screenings meant for men and not the others', () {
    final ids = ruleIdsFor(person(Sex.male, fiftyTwo));
    expect(ids, contains('prostate-exam'));
    expect(ids, contains('aortic-aneurysm'));
    expect(ids, isNot(contains('mammography')));
    expect(ids, isNot(contains('cervical-cotest')));
  });

  test('sex unstated shows both sets, marked as only possibly applying', () {
    // Hiding them would silently drop an entitlement; showing them as due
    // would tell someone to book something they cannot have.
    final schedule = scheduleFor(person(Sex.notStated, fiftyTwo));
    final byRule = {for (final o in schedule) o.rule.id: o};

    expect(byRule['mammography']!.applicability, Applicability.possible);
    expect(byRule['prostate-exam']!.applicability, Applicability.possible);
    expect(byRule['skin-cancer']!.applicability, Applicability.definite);
  });

  test('screenings that have not opened yet are upcoming, not missing', () {
    final young = person(Sex.female, DateTime.utc(2004, 1, 10));
    // The first occurrence per rule: a yearly screening has several, and what
    // is being asserted here is whether the entitlement has opened yet.
    final byRule = <String, OccurrenceStatus>{};
    for (final o in scheduleFor(young)) {
      byRule.putIfAbsent(o.rule.id, () => o.status);
    }

    expect(byRule['chlamydia'], OccurrenceStatus.due);
    expect(byRule['checkup-young'], OccurrenceStatus.due);
    expect(byRule['mammography'], OccurrenceStatus.upcoming);
    expect(byRule['skin-cancer'], OccurrenceStatus.upcoming);
  });

  test('an entitlement that has aged out disappears rather than nagging', () {
    // The chlamydia test runs to the 25th birthday, the one-off check-up to
    // the 35th.
    final ids = ruleIdsFor(person(Sex.female, fiftyTwo));
    expect(ids, isNot(contains('chlamydia')));
    expect(ids, isNot(contains('checkup-young')));
  });

  test('the check-up interval runs from the date it was actually had', () {
    final p = person(Sex.male, DateTime.utc(1980, 11, 2));
    final schedule = scheduleFor(
      p,
      completions: [
        Completion(
          personId: p.id,
          ruleId: 'checkup',
          completedOn: DateTime.utc(2025, 4, 8),
        ),
      ],
    ).where((o) => o.rule.id == 'checkup').toList();

    expect(schedule.first.status, OccurrenceStatus.done);
    expect(
      schedule.firstWhere((o) => o.status != OccurrenceStatus.done).windowStart,
      DateTime.utc(2028, 4, 8),
    );
  });

  test(
    'a yearly screening shows the one that is running, not every year missed',
    () {
      // Somebody who has never recorded a dental or skin check since turning 35
      // should see this year's, not twenty lapsed ones.
      final skin = scheduleFor(
        person(Sex.male, DateTime.utc(1970, 5, 20)),
      ).where((o) => o.rule.id == 'skin-cancer').toList();

      expect(skin, hasLength(lessThanOrEqualTo(3)));
      expect(skin.first.windowStart, DateTime.utc(2025, 5, 20));
      expect(skin.first.status, OccurrenceStatus.due);
    },
  );
}
