import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

void main() {
  final catalogs = CatalogSet([catalogNamed('dental')]);
  final birth = DateTime.utc(2026, 1, 15);
  final child = Person(id: 'p1', name: 'Kind', dateOfBirth: birth);

  List<Occurrence> scheduleFor(Person p, DateTime today) => computeOccurrences(
    person: p,
    catalogs: catalogs,
    completions: const [],
    today: today,
  );

  Occurrence z(String id) =>
      scheduleFor(child, birth).firstWhere((o) => o.rule.id == id);

  test('the six examinations tile the first six years without a gap', () {
    // Teil B of the guideline ends 'zum vollendeten 33. Lebensmonat' and Teil C
    // begins 'ab dem 34. Lebensmonat', which is the same day. A gap here would
    // mean the conversion from Lebensmonat to age is off by one somewhere.
    final windows = [
      for (final id in ['z1', 'z2', 'z3', 'z4', 'z5', 'z6'])
        (z(id).windowStart, z(id).windowEnd!),
    ];

    expect(windows.first.$1, DateTime.utc(2026, 6, 15));
    expect(windows.last.$2, DateTime.utc(2032, 1, 15));
    for (var i = 1; i < windows.length; i++) {
      expect(windows[i].$1, windows[i - 1].$2, reason: 'gap before index $i');
    }
  });

  test('a lapsed examination expires instead of staying overdue', () {
    // Born 2022-10-10, so 47 months old on the pinned today: Z1 to Z3 are
    // over, Z4 is still open until the 48th month.
    final nearlyFour = Person(
      id: 'p5',
      name: 'Kind',
      dateOfBirth: DateTime.utc(2022, 10, 10),
    );
    final byId = {
      for (final o in scheduleFor(nearlyFour, DateTime.utc(2026, 9, 20)))
        o.rule.id: o,
    };

    for (final id in ['z1', 'z2', 'z3']) {
      expect(byId[id]!.status, OccurrenceStatus.expired, reason: id);
    }
    expect(byId['z4']!.status, OccurrenceStatus.due);
    expect(byId['z4']!.deadline, byId['z4']!.windowEnd);
    expect(byId['z5']!.status, OccurrenceStatus.upcoming);
    expect(
      byId.values.map((o) => o.status),
      isNot(contains(OccurrenceStatus.overdue)),
    );
  });

  test('the dental examinations stop at six', () {
    final sevenYearOld = Person(
      id: 'p2',
      name: 'Kind',
      dateOfBirth: DateTime.utc(2019, 1, 15),
    );
    final ids = scheduleFor(
      sevenYearOld,
      DateTime.utc(2026, 9, 20),
    ).map((o) => o.rule.id).toSet();

    expect(ids, isNot(contains('z6')));
    expect(ids, contains('ip-6-11'));
  });

  test('prophylaxis moves to twice a year at twelve', () {
    final thirteen = Person(
      id: 'p3',
      name: 'Kind',
      dateOfBirth: DateTime.utc(2013, 2, 1),
    );
    final schedule = scheduleFor(thirteen, DateTime.utc(2026, 9, 20));
    final halfYearly = schedule
        .where((o) => o.rule.id == 'ip-12-17')
        .map((o) => o.windowStart)
        .toList();

    expect(schedule.map((o) => o.rule.id), isNot(contains('ip-6-11')));
    expect(halfYearly.first, DateTime.utc(2026, 8, 1));
    expect(halfYearly[1], DateTime.utc(2027, 2, 1));
  });

  test('an adult gets one check-up a year, for the prosthesis bonus', () {
    final adult = Person(
      id: 'p4',
      name: 'Erwachsen',
      dateOfBirth: DateTime.utc(1990, 6, 1),
    );
    final schedule = scheduleFor(
      adult,
      DateTime.utc(2026, 9, 20),
    ).where((o) => o.rule.id == 'dental-checkup-adult').toList();

    expect(schedule.first.windowStart, DateTime.utc(2026, 6, 1));
    expect(schedule.first.status, OccurrenceStatus.due);
    expect(schedule[1].windowStart, DateTime.utc(2027, 6, 1));
  });
}
