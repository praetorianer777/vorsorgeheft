import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/occurrence.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/domain/schedule_engine.dart';
import 'package:vorsorgereminder/notifications/reminder.dart';

import '../support/catalogs.dart';

void main() {
  final catalogs = CatalogSet([childrenCatalog()]);

  List<Occurrence> scheduleFor(DateTime birth, DateTime today) =>
      computeOccurrences(
        person: Person(id: 'p1', name: 'Kind', dateOfBirth: birth),
        catalogs: catalogs,
        completions: const [],
        today: today,
      );

  group('planning', () {
    test('warns ahead of a window opening, at the configured time of day', () {
      final occurrences = scheduleFor(
        DateTime.utc(2026, 1, 15),
        DateTime.utc(2026, 9, 20),
      );
      final plan = planReminders(
        occurrences: occurrences,
        now: DateTime(2026, 9, 20, 8),
        settings: const ReminderSettings(maxPending: 100),
      );

      final u9 = plan.where(
        (r) => r.ruleId == 'u9' && r.kind == ReminderKind.windowOpens,
      );
      // The U9 window opens 59 months after birth: 15 December 2030.
      expect(u9.map((r) => r.fireAt).toSet(), {
        DateTime(2030, 11, 15, 9),
        DateTime(2030, 12, 1, 9),
        DateTime(2030, 12, 12, 9),
      });
    });

    test('nothing is scheduled in the past', () {
      final plan = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 1, 15),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 8),
        settings: const ReminderSettings(maxPending: 500),
      );
      expect(
        plan.every((r) => r.fireAt.isAfter(DateTime(2026, 9, 20, 8))),
        isTrue,
      );
    });

    test('a reminder due later today still counts as future', () {
      final plan = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 1, 15),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 3),
        settings: const ReminderSettings(maxPending: 500),
      );
      expect(plan.map((r) => r.fireAt), isNot(contains(DateTime(2026, 9, 20))));
      expect(plan, isNotEmpty);
    });

    test('an exclusion deadline gets its own escalating warnings', () {
      final plan = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 1, 15),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 8),
        settings: const ReminderSettings(maxPending: 500),
      );

      final u6 = plan.where(
        (r) => r.ruleId == 'u6' && r.kind == ReminderKind.deadlineApproaching,
      );
      // The U6 entitlement lapses on 14 March 2027.
      expect(u6.map((r) => r.fireAt).toSet(), {
        DateTime(2027, 2, 12, 9),
        DateTime(2027, 3, 7, 9),
      });
    });

    test('a rule with no exclusion deadline gets no deadline warnings', () {
      final plan = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 1, 15),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 8),
        settings: const ReminderSettings(maxPending: 500),
      );
      expect(
        plan.any(
          (r) =>
              r.ruleId == 'u10' && r.kind == ReminderKind.deadlineApproaching,
        ),
        isFalse,
      );
    });

    test('a settled appointment is not reminded about', () {
      final done = computeOccurrences(
        person: Person(
          id: 'p1',
          name: 'Kind',
          dateOfBirth: DateTime.utc(2026, 1, 15),
        ),
        catalogs: catalogs,
        completions: const [],
        today: DateTime.utc(2026, 9, 20),
      ).where((o) => o.status != OccurrenceStatus.upcoming).toList();

      final plan = planReminders(
        occurrences: done,
        now: DateTime(2026, 9, 20, 8),
        settings: const ReminderSettings(maxPending: 500),
      );
      expect(plan.any((r) => r.ruleId == 'u2'), isFalse);
    });
  });

  group('the platform limits', () {
    test('never more than the cap, and always the soonest ones', () {
      // iOS keeps only the 64 notifications that fire soonest and silently
      // drops the rest. Scheduling everything would mean the ones that get
      // dropped are the ones furthest out - which is fine - but it would also
      // mean the app has no idea which of them survived.
      final occurrences = scheduleFor(
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 9, 20),
      );
      final now = DateTime(2026, 9, 20, 8);

      final capped = planReminders(
        occurrences: occurrences,
        now: now,
        settings: const ReminderSettings(),
      );
      final uncapped = planReminders(
        occurrences: occurrences,
        now: now,
        settings: const ReminderSettings(maxPending: 10000),
      );

      expect(capped, hasLength(20));
      expect(uncapped.length, greaterThan(20));
      expect(
        capped.map((r) => r.fireAt),
        uncapped.take(20).map((r) => r.fireAt),
      );
    });

    test('the plan comes back in firing order', () {
      final plan = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 9, 1),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 8),
      );
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].fireAt.isBefore(plan[i - 1].fireAt), isFalse);
      }
    });
  });

  group('ids', () {
    test('are stable across runs', () {
      // Android replaces a notification with the same id and adds a second one
      // otherwise, so an id that changed between releases would leave stale
      // reminders behind that nothing can cancel.
      expect(
        reminderId('p1-u6', ReminderKind.windowOpens, const Duration(days: 30)),
        reminderId('p1-u6', ReminderKind.windowOpens, const Duration(days: 30)),
      );
    });

    test('differ per occurrence, kind and lead time', () {
      final ids = {
        reminderId('p1-u6', ReminderKind.windowOpens, const Duration(days: 30)),
        reminderId('p1-u7', ReminderKind.windowOpens, const Duration(days: 30)),
        reminderId(
          'p1-u6',
          ReminderKind.deadlineApproaching,
          const Duration(days: 30),
        ),
        reminderId('p1-u6', ReminderKind.windowOpens, const Duration(days: 14)),
      };
      expect(ids, hasLength(4));
    });

    test('fit in a positive 32-bit int', () {
      for (final key in ['p1-u6', 'a' * 200, 'ä-ö-ü']) {
        final id = reminderId(key, ReminderKind.windowOpens, Duration.zero);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(0x80000000));
      }
    });

    test('a replanned occurrence keeps its id', () {
      final first = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 1, 15),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 8),
      );
      final second = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 1, 15),
          DateTime.utc(2026, 9, 21),
        ),
        now: DateTime(2026, 9, 21, 8),
      );
      final overlap = first
          .map((r) => r.occurrenceKey)
          .toSet()
          .intersection(second.map((r) => r.occurrenceKey).toSet());
      expect(overlap, isNotEmpty);
      for (final key in overlap) {
        expect(
          second.where((r) => r.occurrenceKey == key).map((r) => r.id).toSet(),
          containsAll(
            first
                .where((r) => r.occurrenceKey == key)
                .map((r) => r.id)
                .toSet()
                .intersection(
                  second
                      .where((r) => r.occurrenceKey == key)
                      .map((r) => r.id)
                      .toSet(),
                ),
          ),
        );
      }
    });
  });
}
