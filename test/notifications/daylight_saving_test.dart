import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';

import '../support/catalogs.dart';

/// A reminder belongs to nine in the morning where the person is, and twice a
/// year a day there is 23 or 25 hours long.
///
/// Two regressions are possible and neither shows up on an ordinary day.
/// Building the time in UTC hands the platform an instant that is nine
/// o'clock somewhere else - every reminder in the summer half of the year
/// then arrives an hour early. And counting a lead in hours rather than in
/// calendar days moves the reminder to the day before whenever the span
/// crosses a switch. Both are asserted here without reference to the zone
/// this test happens to run in, because a CI runner keeps its clock on UTC
/// and a phone does not.
void main() {
  final catalogs = CatalogSet([childrenCatalog()]);
  final rule = childrenCatalog().rules.first;

  /// Central European Time moves forward on the last Sunday in March and
  /// back on the last Sunday in October.
  final switches = {
    'spring forward': DateTime.utc(2027, 3, 28),
    'fall back': DateTime.utc(2027, 10, 31),
  };

  List<PlannedReminder> planFor(DateTime windowStart, {int leadDays = 30}) =>
      planReminders(
        occurrences: [
          Occurrence(
            personId: 'p1',
            rule: rule,
            windowStart: windowStart,
            status: OccurrenceStatus.upcoming,
          ),
        ],
        now: DateTime(2026, 9, 20, 8),
        settings: ReminderSettings(
          beforeWindowOpens: [Duration(days: leadDays)],
          beforeDeadline: const [],
          maxPending: 10,
        ),
      );

  test('a whole childhood of reminders sits at the configured time', () {
    final plan = planReminders(
      occurrences: computeOccurrences(
        person: Person(
          id: 'p1',
          name: 'Kind',
          dateOfBirth: DateTime.utc(2026, 5, 20),
        ),
        catalogs: catalogs,
        completions: const [],
        today: DateTime.utc(2026, 9, 20),
      ),
      now: DateTime(2026, 9, 20, 8),
      settings: const ReminderSettings(maxPending: 200),
    );

    expect(plan, isNotEmpty);
    for (final reminder in plan) {
      expect(reminder.fireAt.hour, 9, reason: '$reminder');
      expect(reminder.fireAt.minute, 0, reason: '$reminder');
      // A UTC time would be nine o'clock in London, not where the family is.
      expect(reminder.fireAt.isUtc, isFalse, reason: '$reminder');
    }
  });

  group('a lead that crosses a clock change', () {
    for (final entry in switches.entries) {
      final day = entry.value;

      test('lands on the day it should, ${entry.key}', () {
        // Thirty days after the switch, so the reminder falls on the day
        // before it, the day of it and the day after it in turn.
        for (var offset = -1; offset <= 1; offset++) {
          final target = DateTime.utc(
            day.year,
            day.month,
            day.day + 30 + offset,
          );
          final reminder = planFor(target).single;
          final expected = DateTime.utc(day.year, day.month, day.day + offset);
          expect(
            [reminder.fireAt.year, reminder.fireAt.month, reminder.fireAt.day],
            [expected.year, expected.month, expected.day],
            reason: '${entry.key}, offset $offset',
          );
          expect(reminder.fireAt.hour, 9, reason: entry.key);
        }
      });

      test('keeps the full lead in days, ${entry.key}', () {
        final target = DateTime.utc(day.year, day.month, day.day + 14);
        final reminder = planFor(target, leadDays: 30).single;
        final days = DateTime.utc(target.year, target.month, target.day)
            .difference(
              DateTime.utc(
                reminder.fireAt.year,
                reminder.fireAt.month,
                reminder.fireAt.day,
              ),
            );
        expect(days.inDays, 30, reason: entry.key);
      });
    }
  });

  group('three days later, across a clock change', () {
    for (final entry in switches.entries) {
      test('is three calendar days and still nine o\'clock, ${entry.key}', () {
        // "Later" is three days, and the day the clocks move is 23 or 25
        // hours long. Counted in hours the reminder would land at eight or
        // at ten; counted in days it lands at nine, which is what the
        // person agreed to.
        final day = entry.value;
        final pressed = DateTime(day.year, day.month, day.day - 1, 20);
        final until = DateTime.utc(
          pressed.year,
          pressed.month,
          pressed.day + 3,
        );
        final occurrence = Occurrence(
          personId: 'p1',
          rule: rule,
          windowStart: DateTime.utc(day.year, day.month, day.day + 10),
          status: OccurrenceStatus.due,
        );

        final reminder = planReminders(
          occurrences: [occurrence],
          now: pressed,
          settings: const ReminderSettings(maxPending: 10),
          putOff: {occurrence.key: until},
        ).single;

        expect(
          [reminder.fireAt.year, reminder.fireAt.month, reminder.fireAt.day],
          [until.year, until.month, until.day],
          reason: entry.key,
        );
        expect(reminder.fireAt.hour, 9, reason: entry.key);
        expect(reminder.fireAt.isUtc, isFalse, reason: entry.key);
        // Counted as calendar days rather than as elapsed hours, which
        // across a switch differ by one.
        expect(
          until.difference(
            DateTime.utc(pressed.year, pressed.month, pressed.day),
          ),
          const Duration(days: 3),
          reason: entry.key,
        );
      });
    }
  });

  test('a time of day the spring switch skips is still planned for', () {
    // Half past two in the morning does not exist on the day the clocks go
    // forward. What must not happen is the reminder falling out of the plan
    // or moving to another day; the hour itself is what the zone makes of
    // it, which on a phone in Berlin is half past three and on a machine
    // keeping UTC is half past two.
    final day = switches['spring forward']!;
    final plan = planReminders(
      occurrences: [
        Occurrence(
          personId: 'p1',
          rule: rule,
          windowStart: DateTime.utc(day.year, day.month, day.day + 3),
          status: OccurrenceStatus.upcoming,
        ),
      ],
      now: DateTime(2026, 9, 20, 8),
      settings: const ReminderSettings(
        hour: 2,
        minute: 30,
        beforeWindowOpens: [Duration(days: 3)],
        beforeDeadline: [],
        maxPending: 10,
      ),
    );

    expect(plan, hasLength(1));
    expect(plan.single.fireAt.day, day.day);
    expect(plan.single.fireAt.minute, 30);
    expect(plan.single.fireAt.hour, anyOf(2, 3));
  });
}
