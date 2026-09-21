import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/age_offset.dart';

void main() {
  group('applyTo', () {
    test('adds calendar months rather than 30-day blocks', () {
      expect(
        const AgeOffset(months: 1).applyTo(DateTime.utc(2026, 1, 15)),
        DateTime.utc(2026, 2, 15),
      );
      expect(
        const AgeOffset(months: 1).applyTo(DateTime.utc(2026, 3, 15)),
        DateTime.utc(2026, 4, 15),
      );
    });

    test('clamps to the last day of a shorter target month', () {
      expect(
        const AgeOffset(months: 1).applyTo(DateTime.utc(2026, 5, 31)),
        DateTime.utc(2026, 6, 30),
      );
      expect(
        const AgeOffset(months: 1).applyTo(DateTime.utc(2026, 1, 31)),
        DateTime.utc(2026, 2, 28),
      );
    });

    test('lands a leap-day birthday on 28 February in a common year', () {
      expect(
        const AgeOffset(years: 1).applyTo(DateTime.utc(2024, 2, 29)),
        DateTime.utc(2025, 2, 28),
      );
      expect(
        const AgeOffset(years: 4).applyTo(DateTime.utc(2024, 2, 29)),
        DateTime.utc(2028, 2, 29),
      );
    });

    test('crosses year boundaries', () {
      expect(
        const AgeOffset(months: 14).applyTo(DateTime.utc(2025, 11, 10)),
        DateTime.utc(2027, 1, 10),
      );
      expect(
        const AgeOffset(months: -2).applyTo(DateTime.utc(2026, 1, 10)),
        DateTime.utc(2025, 11, 10),
      );
    });

    test('keeps the hours the newborn screenings are measured in', () {
      final birth = DateTime.utc(2026, 3, 1, 22, 30);
      expect(
        const AgeOffset(hours: 36).applyTo(birth),
        DateTime.utc(2026, 3, 3, 10, 30),
      );
    });

    test('applies calendar units before fixed ones', () {
      expect(
        const AgeOffset(months: 1, days: 1).applyTo(DateTime.utc(2026, 1, 31)),
        DateTime.utc(2026, 3, 1),
      );
    });
  });

  group('fromJson', () {
    test('defaults every unit to zero', () {
      expect(AgeOffset.fromJson({'months': 3}), const AgeOffset(months: 3));
      expect(AgeOffset.fromJson(<String, Object?>{}).isZero, isTrue);
    });

    test('rejects an unknown unit rather than ignoring it', () {
      expect(
        () => AgeOffset.fromJson({'monts': 3}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('monts'),
          ),
        ),
      );
    });

    test('rejects a non-integer value', () {
      expect(() => AgeOffset.fromJson({'months': 1.5}), throwsFormatException);
    });
  });
}
