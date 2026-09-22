import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';

import '../support/catalogs.dart';

/// Walks a person through every month of the first year and every year up to
/// twenty, once as a girl and once as a boy, and checks what the app shows
/// against the G-BA and STIKO tables.
///
/// The expectations below are written from the guidelines, not read off the
/// catalogs, so a wrong window in a catalog fails here. An appointment is
/// "open" when its window has opened and it can still be had (due or
/// overdue); "lapsed" when its exclusion deadline has passed. Ages that fall
/// exactly on a window edge are left out of the expectations, because a
/// window that ends "at 9 months" is inclusive of that day and a test on
/// that day would only be testing the edge convention.
void main() {
  final today = DateTime.utc(2026, 9, 22);
  final catalogs = shippedCatalogs();

  DateTime bornAgo({int years = 0, int months = 0}) =>
      DateTime.utc(today.year - years, today.month - months, today.day);

  String label(Occurrence o) =>
      o.doseId == null ? o.rule.id : '${o.rule.id}#${o.doseId}';

  List<Occurrence> timelineOf(Sex sex, DateTime birth) => computeOccurrences(
    person: Person(id: 'p', name: 'P', dateOfBirth: birth, sex: sex),
    catalogs: catalogs,
    completions: const [],
    today: today,
  );

  Set<String> withStatus(List<Occurrence> t, Set<OccurrenceStatus> s) => {
    for (final o in t)
      if (s.contains(o.status)) label(o),
  };

  const open = {OccurrenceStatus.due, OccurrenceStatus.overdue};

  // The infant series, spelled out once: the six-in-one, the pneumococcal
  // and the meningococcal B vaccinations start at two months, with the
  // second dose at four and the third at eleven (twelve for MenB).
  const firstDoses = [
    'six-in-one#g1',
    'pneumococcal-infant#g1',
    'meningococcal-b#g1',
  ];
  const secondDoses = [
    'six-in-one#g2',
    'pneumococcal-infant#g2',
    'meningococcal-b#g2',
  ];

  final expectations = <String, _Expect>{
    // Straight after birth: U1, the hearing screening and the RSV
    // immunisation, which the STIKO recommends for every infant in its first
    // season.
    'month 0': _Expect(open: ['u1', 'hearing-screening', 'rsv-infant']),
    // One month: the U3 (3rd to 5th week) is open. The U1 lapsed with the day
    // of birth, the U2 and the screenings with a two-week limit after it, and
    // the blood screenings with the fourth week.
    'month 1': _Expect(
      open: ['u3', 'rsv-infant'],
      lapsed: [
        'u1',
        'u2',
        'hearing-screening',
        'pulse-oximetry',
        'cf-screening',
        'newborn-screening',
      ],
    ),
    // Two months: U4 opens, and with it the first doses; rotavirus from six
    // weeks. The U3 could be caught up until the end of the eighth week.
    'month 2': _Expect(
      open: ['u4', 'rotavirus#g1', ...firstDoses, 'rsv-infant'],
      lapsed: ['u3'],
    ),
    'month 3': _Expect(
      open: ['u4', 'rotavirus#g1', 'rotavirus#g2', ...firstDoses, 'rsv-infant'],
    ),
    // Four months: the U4 window (2nd to 4th month) has closed but the U4
    // can still be caught up for two weeks; the second doses open.
    'month 4': _Expect(
      open: [
        'u4',
        'rotavirus#g1',
        'rotavirus#g2',
        'rotavirus#g3',
        ...firstDoses,
        ...secondDoses,
        'rsv-infant',
      ],
    ),
    // Five months: U5 (5th to 7th month) and the first dental check (FU1,
    // 6th to 9th month per the G-BA, counted from the completed fifth).
    'month 5': _Expect(
      open: ['u5', 'z1', ...firstDoses, ...secondDoses, 'rsv-infant'],
      lapsed: ['u4'],
    ),
    'month 6': _Expect(
      open: ['u5', 'z1', ...firstDoses, ...secondDoses, 'rsv-infant'],
    ),
    // Seven months: U5 overdue but not lapsed (limit: end of 8th month).
    'month 7': _Expect(
      open: ['u5', 'z1', ...firstDoses, ...secondDoses, 'rsv-infant'],
    ),
    // Eight months: U5 lapsed. Rotavirus is no longer given after 32 weeks
    // and must have left the timeline entirely.
    'month 8': _Expect(
      open: ['z1', ...firstDoses, ...secondDoses, 'rsv-infant'],
      lapsed: ['u5'],
      absent: ['rotavirus#g1', 'rotavirus#g2', 'rotavirus#g3'],
    ),
    // Nine months: U6 (9th to 12th month) and FU2 open; FU1 ends today.
    'month 9': _Expect(
      open: ['u6', 'z2', ...firstDoses, ...secondDoses, 'rsv-infant'],
    ),
    'month 10': _Expect(
      open: ['u6', 'z2', ...firstDoses, ...secondDoses, 'rsv-infant'],
      lapsed: ['z1'],
    ),
    // Eleven months: the third doses of six-in-one and pneumococcal, and the
    // first MMR and varicella.
    'month 11': _Expect(
      open: [
        'u6',
        'z2',
        ...firstDoses,
        ...secondDoses,
        'six-in-one#g3',
        'pneumococcal-infant#g3',
        'mmr#g1',
        'varicella#g1',
        'rsv-infant',
      ],
    ),
    // One year: U6 overdue (limit: end of 14th month), MenB third dose.
    'year 1': _Expect(
      open: [
        'u6',
        'z2',
        ...firstDoses,
        ...secondDoses,
        'six-in-one#g3',
        'pneumococcal-infant#g3',
        'meningococcal-b#g3',
        'mmr#g1',
        'varicella#g1',
      ],
    ),
    // Two years: U7 (21st to 24th month) overdue, FU3, second MMR and
    // varicella from 15 months.
    'year 2': _Expect(
      open: ['u7', 'z3', 'mmr#g1', 'mmr#g2', 'varicella#g1', 'varicella#g2'],
      lapsed: ['u6'],
      absent: ['rsv-infant'],
    ),
    // Three years: U7a (34th to 36th month) overdue, U7 lapsed, FU4.
    'year 3': _Expect(open: ['u7a', 'z4'], lapsed: ['u7', 'z3']),
    // Four years: U8 (46th to 48th month) overdue, U7a lapsed, FU5.
    'year 4': _Expect(open: ['u8', 'z5'], lapsed: ['u7a']),
    // Five years: U9 (60th to 64th month), FU6 and the preschool tetanus
    // booster (5 to 6 years).
    'year 5': _Expect(
      open: ['u9', 'z6', 'tdap-booster-preschool'],
      lapsed: ['u8'],
    ),
    // Six years: the yearly individual prophylaxis (IP) at the dentist
    // starts; U9 lapsed (limit: end of 66th month).
    'year 6': _Expect(
      open: ['ip-6-11', 'tdap-booster-preschool'],
      lapsed: ['u9'],
    ),
    // Seven: U10, which is not a statutory benefit.
    'year 7': _Expect(open: ['u10', 'ip-6-11']),
    'year 8': _Expect(open: ['u10', 'ip-6-11', 'tdap-booster-preschool']),
    // Nine: U11, the teenage Tdap-IPV booster (9 to 16) and HPV (9 to 14).
    'year 9': _Expect(
      open: ['u11', 'u10', 'ip-6-11', 'tdap-ipv-booster-teen', 'hpv#g1'],
    ),
    'year 10': _Expect(
      open: ['u11', 'ip-6-11', 'tdap-ipv-booster-teen', 'hpv#g1', 'hpv#g2'],
    ),
    'year 11': _Expect(open: ['u11', 'tdap-ipv-booster-teen', 'hpv#g1']),
    // Twelve: IP twice a year, MenACWY (12 to 14).
    'year 12': _Expect(
      open: [
        'ip-12-17',
        'meningococcal-acwy',
        'tdap-ipv-booster-teen',
        'hpv#g1',
        'hpv#g2',
      ],
    ),
    // Thirteen: J1 (13 to 14).
    'year 13': _Expect(
      open: ['j1', 'ip-12-17', 'meningococcal-acwy', 'tdap-ipv-booster-teen'],
    ),
    'year 14': _Expect(
      open: ['j1', 'ip-12-17', 'tdap-ipv-booster-teen', 'hpv#g1', 'hpv#g2'],
    ),
    'year 15': _Expect(open: ['ip-12-17', 'tdap-ipv-booster-teen', 'hpv#g2']),
    // Sixteen: J2 (not statutory), J1 lapsed, chlamydia screening for young
    // women from 16 (the G-BA grants it until 25).
    'year 16': _Expect(
      open: ['j2', 'ip-12-17', 'tdap-ipv-booster-teen', 'meningococcal-acwy'],
      lapsed: ['j1'],
      female: ['chlamydia'],
    ),
    'year 17': _Expect(
      open: ['j2', 'ip-12-17', 'meningococcal-acwy'],
      female: ['chlamydia'],
    ),
    // Eighteen: the adult catalog starts. One check-up between 18 and 34,
    // the yearly dental check, measles for adults born after 1970, and the
    // Td booster ten years after the teenage one.
    'year 18': _Expect(
      open: [
        'checkup-young',
        'dental-checkup-adult',
        'measles-adult',
        'td-booster',
      ],
      female: ['chlamydia'],
    ),
    'year 19': _Expect(
      open: [
        'checkup-young',
        'dental-checkup-adult',
        'measles-adult',
        'td-booster',
      ],
      female: ['chlamydia'],
    ),
    // Twenty: cervical cytology and the gynaecological examination for women.
    'year 20': _Expect(
      open: [
        'checkup-young',
        'dental-checkup-adult',
        'measles-adult',
        'td-booster',
      ],
      female: ['chlamydia', 'cervical-cytology', 'gynaecological-exam'],
      absent: ['u10', 'u11', 'j1', 'j2', 'ip-12-17'],
    ),
  };

  const womenOnly = {
    'chlamydia',
    'cervical-cytology',
    'cervical-cotest',
    'gynaecological-exam',
    'mammography',
    'pertussis-pregnancy',
  };
  const menOnly = {'prostate-exam', 'aortic-aneurysm'};

  final ages = <String, DateTime>{
    for (var m = 0; m < 12; m++) 'month $m': bornAgo(months: m),
    for (var y = 1; y <= 20; y++) 'year $y': bornAgo(years: y),
  };

  for (final sex in [Sex.female, Sex.male]) {
    group(sex == Sex.female ? 'a girl' : 'a boy', () {
      for (final entry in ages.entries) {
        final expected = expectations[entry.key]!;
        final sexSpecific = sex == Sex.female
            ? expected.female
            : const <String>[];

        test('at ${entry.key} sees what the guidelines say', () {
          final timeline = timelineOf(sex, entry.value);
          final openNow = withStatus(timeline, open);
          // Nothing that can only happen at birth is ever left open after the
          // first month.
          if (entry.key != 'month 0') {
            expect(openNow, isNot(contains('u1')));
            expect(openNow, isNot(contains('newborn-screening')));
          }
          final lapsed = withStatus(timeline, {OccurrenceStatus.expired});
          final all = timeline.map(label).toSet();

          for (final id in [...expected.open, ...sexSpecific]) {
            expect(openNow, contains(id), reason: '$id should be open');
          }
          for (final id in expected.lapsed) {
            expect(lapsed, contains(id), reason: '$id should have lapsed');
          }
          for (final id in expected.absent) {
            expect(all, isNot(contains(id)), reason: '$id should be gone');
          }
          final other = sex == Sex.female ? menOnly : womenOnly;
          expect(all.where(other.contains), isEmpty);
          // The list is never shown as due for something that does not apply
          // and never shows something twice.
          expect(timeline.map((o) => o.key).toSet().length, timeline.length);
        });

        test('at ${entry.key} is reminded of what is about to open', () {
          final timeline = timelineOf(sex, entry.value);
          final plan = planReminders(
            occurrences: timeline,
            now: today,
            settings: const ReminderSettings(maxPending: 1000),
          );
          final remindedKeys = plan.map((r) => r.occurrenceKey).toSet();
          final soon = today.add(const Duration(days: 30));

          for (final o in timeline) {
            final opensSoon =
                o.status == OccurrenceStatus.upcoming &&
                o.windowStart.isAfter(today) &&
                !o.windowStart.isAfter(soon);
            final deadline = o.deadline;
            final lapsesSoon =
                o.isOpen &&
                deadline != null &&
                deadline.isAfter(today.add(const Duration(days: 3))) &&
                !deadline.isAfter(soon);
            if (opensSoon || lapsesSoon) {
              expect(
                remindedKeys,
                contains(o.key),
                reason: '${label(o)} (${o.status.name}) needs a reminder',
              );
            }
            if (!o.isOpen) {
              expect(remindedKeys, isNot(contains(o.key)));
            }
          }
          for (final r in plan) {
            expect(r.fireAt.isAfter(today), isTrue);
          }
        });
      }
    });
  }

  test('every rule for the first twenty years is reached by the walk', () {
    final seen = <String>{};
    for (final sex in [Sex.female, Sex.male]) {
      for (final birth in ages.values) {
        seen.addAll(timelineOf(sex, birth).map((o) => o.rule.id));
      }
    }
    final expectedRules = [
      for (final rule in catalogs.rulesFor(Species.human))
        if (!rule.optional &&
            (rule.eligibility.maxAge == null ||
                rule.eligibility.maxAge!.years <= 25))
          rule.id,
      'checkup-young',
      'chlamydia',
      'cervical-cytology',
      'gynaecological-exam',
      'dental-checkup-adult',
      'measles-adult',
      'td-booster',
    ];
    for (final id in expectedRules) {
      expect(seen, contains(id), reason: '$id never appears before 21');
    }
  });
}

class _Expect {
  const _Expect({
    this.open = const [],
    this.lapsed = const [],
    this.absent = const [],
    this.female = const [],
  });

  final List<String> open;
  final List<String> lapsed;
  final List<String> absent;
  final List<String> female;
}
