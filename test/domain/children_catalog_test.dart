import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/localized_text.dart';
import 'package:vorsorgereminder/domain/occurrence.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/domain/schedule.dart';
import 'package:vorsorgereminder/domain/schedule_engine.dart';

void main() {
  final catalog = Catalog.parse(
    File('assets/catalogs/children.json').readAsStringSync(),
  );
  final catalogs = CatalogSet([catalog]);

  // Pinned so the expected dates below can be checked by hand against the
  // guideline, and so the suite does not start failing as the calendar moves.
  final birth = DateTime.utc(2026, 1, 15);
  final child = Person(id: 'p1', name: 'Kind', dateOfBirth: birth);

  Occurrence occurrenceFor(String ruleId, {DateTime? today}) =>
      computeOccurrences(
        person: child,
        catalogs: catalogs,
        completions: const [],
        today: today ?? DateTime.utc(2026, 1, 15),
      ).firstWhere((o) => o.rule.id == ruleId);

  test('the shipped catalog parses', () {
    expect(catalog.id, 'children');
    expect(catalog.rules, hasLength(18));
  });

  test('every rule names a source with an as-of date', () {
    for (final rule in catalog.rules) {
      expect(rule.source.url, startsWith('https://'), reason: rule.id);
      expect(rule.source.asOf, isNotNull, reason: rule.id);
    }
  });

  test('every rule reads in both languages', () {
    for (final rule in catalog.rules) {
      for (final locale in LocalizedText.supportedLocales) {
        expect(rule.title(locale), isNotEmpty, reason: '${rule.id}/$locale');
        expect(
          rule.description(locale),
          isNotEmpty,
          reason: '${rule.id}/$locale',
        );
      }
    }
  });

  group('windows match the Kinder-Richtlinie', () {
    // Guideline § 2: period and tolerance limit per examination, converted from
    // "n. Lebensmonat" to an age as documented in the catalog's _conversion.
    void check(
      String id, {
      required DateTime start,
      required DateTime end,
      required DateTime deadline,
    }) {
      test(id, () {
        final o = occurrenceFor(id);
        expect(o.windowStart, start, reason: '$id start');
        expect(o.windowEnd, end, reason: '$id end');
        expect(o.deadline, deadline, reason: '$id deadline');
      });
    }

    // U2: 3rd-10th day of life, tolerance 3rd-14th.
    check(
      'u2',
      start: DateTime.utc(2026, 1, 17),
      end: DateTime.utc(2026, 1, 24),
      deadline: DateTime.utc(2026, 1, 28),
    );
    // U3: 4th-5th week of life, tolerance 3rd-8th.
    check(
      'u3',
      start: DateTime.utc(2026, 2, 5),
      end: DateTime.utc(2026, 2, 18),
      deadline: DateTime.utc(2026, 3, 11),
    );
    // U5: 6th-7th month of life, tolerance 5th-8th.
    check(
      'u5',
      start: DateTime.utc(2026, 6, 15),
      end: DateTime.utc(2026, 8, 14),
      deadline: DateTime.utc(2026, 9, 14),
    );
    // U6: 10th-12th month of life, tolerance 9th-14th.
    check(
      'u6',
      start: DateTime.utc(2026, 10, 15),
      end: DateTime.utc(2027, 1, 14),
      deadline: DateTime.utc(2027, 3, 14),
    );
    // U9: 60th-64th month of life, tolerance 58th-66th.
    check(
      'u9',
      start: DateTime.utc(2030, 12, 15),
      end: DateTime.utc(2031, 5, 14),
      deadline: DateTime.utc(2031, 7, 14),
    );
    // J1: between the 13th and 14th birthday, tolerance a year either side.
    check(
      'j1',
      start: DateTime.utc(2039, 1, 15),
      end: DateTime.utc(2040, 1, 15),
      deadline: DateTime.utc(2041, 1, 15),
    );
  });

  test('the newborn screenings are measured in hours, not months', () {
    final screening = occurrenceFor('newborn-screening');
    expect(screening.windowStart, DateTime.utc(2026, 1, 16, 12));
    expect(screening.windowEnd, DateTime.utc(2026, 1, 18));

    final pulse = occurrenceFor('pulse-oximetry');
    expect(pulse.windowStart, DateTime.utc(2026, 1, 16));
    expect(pulse.windowEnd, DateTime.utc(2026, 1, 17));
  });

  test('every U examination and the J1 has an exclusion deadline', () {
    final statutory = catalog.rules.where(
      (r) => RegExp(r'^(u[2-9]|u7a|j1)$').hasMatch(r.id),
    );
    expect(statutory, hasLength(10));
    for (final rule in statutory) {
      final schedule = rule.schedule as AgeWindow;
      expect(schedule.hardDeadline, isTrue, reason: rule.id);
      expect(schedule.toleranceTo, isNotNull, reason: rule.id);
    }
  });

  test('U10, U11 and J2 are flagged as not a standard benefit', () {
    for (final id in ['u10', 'u11', 'j2']) {
      expect(catalog.ruleById(id)!.statutory, isFalse, reason: id);
    }
    for (final rule in catalog.rules.where(
      (r) => !['u10', 'u11', 'j2'].contains(r.id),
    )) {
      expect(rule.statutory, isTrue, reason: rule.id);
    }
  });

  group('the U6 deadline behaves as an exclusion deadline', () {
    test('is due inside the window', () {
      expect(
        occurrenceFor('u6', today: DateTime.utc(2026, 12, 1)).status,
        OccurrenceStatus.due,
      );
    });

    test('is overdue but catchable past the window', () {
      expect(
        occurrenceFor('u6', today: DateTime.utc(2027, 2, 1)).status,
        OccurrenceStatus.overdue,
      );
    });

    test('is still catchable on the tolerance limit', () {
      expect(
        occurrenceFor('u6', today: DateTime.utc(2027, 3, 14)).status,
        OccurrenceStatus.overdue,
      );
    });

    test('has expired the day after', () {
      expect(
        occurrenceFor('u6', today: DateTime.utc(2027, 3, 15)).status,
        OccurrenceStatus.expired,
      );
    });

    test('a completion recorded late still counts', () {
      final o = computeOccurrences(
        person: child,
        catalogs: catalogs,
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'u6',
            completedOn: DateTime.utc(2027, 2, 20),
          ),
        ],
        today: DateTime.utc(2027, 6, 1),
      ).firstWhere((o) => o.rule.id == 'u6');
      expect(o.status, OccurrenceStatus.done);
    });
  });

  test('a newborn sees the whole programme ahead of them', () {
    final occurrences = computeOccurrences(
      person: child,
      catalogs: catalogs,
      completions: const [],
      today: birth,
    );
    expect(occurrences, hasLength(18));
    expect(occurrences.map((o) => o.rule.id).take(3), [
      'u1',
      'hearing-screening',
      'pulse-oximetry',
    ]);
  });
}
