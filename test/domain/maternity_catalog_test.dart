import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/rule.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

/// The maternity guideline counts in completed weeks since the last period,
/// written 8+0 for eight weeks and no days. What a person knows is the
/// expected date, which is 40+0, so everything here is checked by asking
/// what the app shows on a given day of a pregnancy.
/// Stands for "not passed", so that null can mean "not pregnant".
const _keep = Object();

void main() {
  final catalogs = shippedCatalogs();
  final expectedOn = DateTime.utc(2027, 4, 1);

  /// The day on which the pregnancy is in week [weeks] plus [days].
  DateTime at(int weeks, [int days = 0]) => expectedOn.subtract(
    Anchor.pregnancyLength - Duration(days: weeks * 7 + days),
  );

  Person mother({DateTime? expecting}) => Person(
    id: 'sara',
    name: 'Sara',
    dateOfBirth: DateTime.utc(1994, 3, 8),
    sex: Sex.female,
    expectingOn: expecting,
    optionalRules: const {'pregnancy-anti-d'},
  );

  /// [expecting] defaults to the date above; pass null for someone who is
  /// not pregnant.
  List<Occurrence> on(
    DateTime day, {
    Object? expecting = _keep,
    Duration horizon = const Duration(days: 90),
  }) => computeOccurrences(
    person: mother(
      expecting: expecting == _keep ? expectedOn : expecting as DateTime?,
    ),
    catalogs: catalogs,
    completions: const [],
    today: day,
    horizon: horizon,
  ).where((o) => o.rule.catalogId == 'maternity').toList();

  Set<String> dueOn(DateTime day) => {
    for (final o in on(day))
      if (o.status == OccurrenceStatus.due) o.rule.id,
  };

  test('nothing from the maternity catalog without an expected date', () {
    expect(on(at(20), expecting: null), isEmpty);
  });

  test('the three ultrasound screenings fall in the weeks they should', () {
    // 8+0 to 11+6, 18+0 to 21+6, 28+0 to 31+6.
    for (final (id, first, last) in [
      ('pregnancy-ultrasound-1', 8, 11),
      ('pregnancy-ultrasound-2', 18, 21),
      ('pregnancy-ultrasound-3', 28, 31),
    ]) {
      expect(dueOn(at(first)), contains(id), reason: '$id at $first+0');
      expect(dueOn(at(last, 6)), contains(id), reason: '$id at $last+6');
      expect(
        dueOn(at(first, -1)),
        isNot(contains(id)),
        reason: '$id is not yet due the day before',
      );
      expect(
        dueOn(at(last + 1)),
        isNot(contains(id)),
        reason: '$id has closed by $last+7',
      );
    }
  });

  test('a screening whose weeks have passed is gone, not overdue', () {
    final later = on(
      at(14),
    ).singleWhere((o) => o.rule.id == 'pregnancy-ultrasound-1');
    expect(later.status, OccurrenceStatus.expired);
  });

  test('the diabetes screening and the antibody test sit where they do', () {
    expect(dueOn(at(24)), contains('pregnancy-diabetes'));
    expect(dueOn(at(27, 6)), contains('pregnancy-diabetes'));
    expect(dueOn(at(23)), contains('pregnancy-antibody-test'));
    expect(dueOn(at(26, 6)), contains('pregnancy-antibody-test'));
    expect(dueOn(at(27)), isNot(contains('pregnancy-antibody-test')));
  });

  test('the Anti-D prophylaxis is a switch, and off by default', () {
    final without = computeOccurrences(
      person: Person(
        id: 'sara',
        name: 'Sara',
        dateOfBirth: DateTime.utc(1994, 3, 8),
        sex: Sex.female,
        expectingOn: expectedOn,
      ),
      catalogs: catalogs,
      completions: const [],
      today: at(28),
    );
    expect(without.map((o) => o.rule.id), isNot(contains('pregnancy-anti-d')));
    expect(dueOn(at(28)), contains('pregnancy-anti-d'));
    expect(dueOn(at(29, 6)), contains('pregnancy-anti-d'));
  });

  test('check-ups run every four weeks, then every two', () {
    final start = expectedOn.subtract(Anchor.pregnancyLength);
    int weekOf(DateTime day) => day.difference(start).inDays ~/ 7;
    final weeks = [
      for (final o in on(at(12), horizon: const Duration(days: 300)))
        if (o.rule.id.startsWith('pregnancy-checkup')) weekOf(o.windowStart),
    ]..sort();

    expect(weeks.where((w) => w < 32), [12, 16, 20, 24, 28]);
    expect(weeks.where((w) => w >= 32 && w <= 40), [32, 34, 36, 38, 40]);
  });

  test('what she is shown is the next three months of them', () {
    // The whole plan is nine months of appointments and nobody books the
    // 38th week in the 12th. The timeline reaches as far as the rest of it
    // does, and the later ones arrive as the pregnancy does.
    int weekOf(DateTime day) =>
        day.difference(expectedOn.subtract(Anchor.pregnancyLength)).inDays ~/ 7;
    final weeks = [
      for (final o in on(at(12)))
        if (o.rule.id.startsWith('pregnancy-checkup')) weekOf(o.windowStart),
    ]..sort();
    // The 32nd week is the first of the fortnightly rule, and a rule's first
    // appointment is always shown however far off it is - the same reason a
    // twenty-year-old sees that the check-up starts at 35.
    expect(weeks, [12, 16, 20, 24, 32]);

    final later = [
      for (final o in on(at(32)))
        if (o.rule.id.startsWith('pregnancy-checkup')) weekOf(o.windowStart),
    ]..sort();
    // The four-weekly appointment of the 28th week runs to the 32nd, so on
    // that day it is still open alongside the fortnightly ones.
    expect(later, [28, 32, 34, 36, 38, 40]);
  });

  test('the check-up after the birth comes six weeks after the date', () {
    expect(dueOn(at(46)), contains('pregnancy-postnatal'));
    expect(dueOn(at(40)), isNot(contains('pregnancy-postnatal')));
  });

  test('clearing the date takes the whole catalog away again', () {
    expect(on(at(30)), isNotEmpty);
    expect(on(at(30), expecting: null), isEmpty);
    // And the rest of her timeline is untouched either way.
    final adult = computeOccurrences(
      person: mother(expecting: null),
      catalogs: catalogs,
      completions: const [],
      today: at(30),
    );
    expect(adult.map((o) => o.rule.catalogId).toSet(), isNot(isEmpty));
  });
}
