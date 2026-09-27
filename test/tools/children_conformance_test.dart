import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/age_offset.dart';
import 'package:vorsorgeheft/domain/schedule.dart';

import '../support/catalogs.dart';

/// Reads the table in § 2 of the Kinder-Richtlinie and holds the catalog to
/// it.
///
/// The nightly watch already notices when the guideline changes and files
/// the diff; deciding what the diff means for the catalog was left to
/// whoever read it. The table is machine-readable enough to do better: name,
/// period, tolerance limit, ten rows. A window that drifts now turns a test
/// red and names the row.
///
/// The conversion is the one children.json documents: German guidelines
/// count periods of life beginning at birth, so the "10. Lebensmonat" starts
/// at the age of nine months, and a period that runs "to the 12th month"
/// ends the day before the twelfth month is complete.
void main() {
  final document = File(
    'tools/catalog-sources/gba-kinder-rl.txt',
  ).readAsStringSync();
  final catalog = childrenCatalog();
  final birth = DateTime.utc(2020, 1, 15);

  DateTime at(AgeOffset offset) => offset.applyTo(birth);
  DateTime after({int months = 0, int weeks = 0, int days = 0}) =>
      AgeOffset(months: months, weeks: weeks, days: days).applyTo(birth);

  /// One row of the table: `U6  10.-12. Lebensmonat  9.-14. Lebensmonat`.
  final rows = <String, List<_Span>>{};
  for (final line in document.split('\n')) {
    final match = RegExp(
      r'^\s{1,3}(U\d+a?)\s{2,}(\S.*?)\s*$',
    ).firstMatch(line.replaceAll('\r', ''));
    if (match == null) continue;
    final spans = _Span.parseAll(match.group(2)!);
    // The table is the only place the examinations are listed with their
    // periods; every other mention of "U6" is prose.
    if (spans.isEmpty && !match.group(2)!.contains('nach der Geburt')) continue;
    rows.putIfAbsent(match.group(1)!.toLowerCase(), () => spans);
  }

  test('the table still reads as ten examinations with their periods', () {
    expect(rows.keys, [
      'u1',
      'u2',
      'u3',
      'u4',
      'u5',
      'u6',
      'u7',
      'u7a',
      'u8',
      'u9',
    ], reason: 'the table in § 2 no longer parses as it did');
    expect(rows['u1'], isEmpty, reason: 'the U1 has no period, it is at birth');
    for (final entry in rows.entries.where((e) => e.key != 'u1')) {
      expect(
        entry.value,
        hasLength(2),
        reason: '${entry.key}: a period and a tolerance limit',
      );
    }
  });

  test('the catalog carries exactly the examinations the table lists', () {
    final inCatalog = catalog.rules
        .map((r) => r.id)
        .where((id) => RegExp(r'^u\d+a?$').hasMatch(id))
        .toSet();
    // U10 and U11 are in the catalog and not in this table: they are not a
    // statutory entitlement and the catalog marks them as such.
    expect(inCatalog.difference(rows.keys.toSet()), {'u10', 'u11'});
    expect(rows.keys.toSet().difference(inCatalog), isEmpty);
  });

  group('every window matches the guideline', () {
    for (final id in ['u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u7a', 'u8', 'u9']) {
      test(id, () {
        final spans = rows[id]!;
        final period = spans[0];
        final tolerance = spans[1];
        final schedule = catalog.rules.singleWhere((r) => r.id == id).schedule;
        expect(schedule, isA<AgeWindow>(), reason: id);
        final window = schedule as AgeWindow;

        expect(
          at(window.from),
          period.opens(birth),
          reason: '$id opens with the ${period.first}. ${period.unit}',
        );
        expect(
          at(window.to),
          period.closes(birth),
          reason: '$id closes with the ${period.last}. ${period.unit}',
        );
        final limit = window.toleranceTo;
        expect(limit, isNotNull, reason: '$id has a tolerance limit');
        if (tolerance.half) {
          // "4 ½ Lebensmonat" names no day, so the catalog rounds; what can
          // be held is that it lands inside that half month.
          expect(
            at(limit!).isAfter(after(months: tolerance.last)),
            isTrue,
            reason: id,
          );
          expect(
            at(limit).isBefore(after(months: tolerance.last + 1)),
            isTrue,
            reason: id,
          );
        } else {
          expect(
            at(limit!),
            tolerance.closes(birth),
            reason:
                '$id may be caught up to the ${tolerance.last}. '
                '${tolerance.unit}',
          );
        }
        // Past the tolerance limit the entitlement is gone, which is the
        // whole point of the table.
        expect(window.hardDeadline, isTrue, reason: id);
      });
    }
  });
}

/// A span of life as the guideline writes it: "3.-10. Lebenstag".
class _Span {
  const _Span(this.first, this.last, this.unit, {this.half = false});

  static final _pattern = RegExp(
    r'(\d+)\.?\s*-\s*(\d+)\s*(½)?\.?\s*(Lebenstag|Lebenswoche|Lebensmonat)',
  );

  static List<_Span> parseAll(String text) => [
    for (final match in _pattern.allMatches(text))
      _Span(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        match.group(4)!,
        half: match.group(3) != null,
      ),
  ];

  final int first;
  final int last;
  final String unit;
  final bool half;

  AgeOffset get _one => switch (unit) {
    'Lebenstag' => const AgeOffset(days: 1),
    'Lebenswoche' => const AgeOffset(weeks: 1),
    _ => const AgeOffset(months: 1),
  };

  /// The day the period opens: the nth period of life begins n-1 periods
  /// after birth.
  DateTime opens(DateTime birth) => _multiple(first - 1).applyTo(birth);

  /// The last day of the period, which is the day before the next one.
  DateTime closes(DateTime birth) =>
      _multiple(last).applyTo(birth).subtract(const Duration(days: 1));

  AgeOffset _multiple(int times) => switch (unit) {
    'Lebenstag' => AgeOffset(days: times * _one.days),
    'Lebenswoche' => AgeOffset(weeks: times * _one.weeks),
    _ => AgeOffset(months: times * _one.months),
  };

  @override
  String toString() => '$first.-$last.${half ? ' ½' : ''} $unit';
}
