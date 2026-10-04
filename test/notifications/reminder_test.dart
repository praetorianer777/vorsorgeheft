import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';

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

    test('a window opening within the shortest lead is still announced', () {
      // Born today: the newborn screening opens in 36 hours, inside every
      // lead. One reminder fires at the next nine o'clock instead of none.
      final plan = planReminders(
        occurrences: scheduleFor(
          DateTime.utc(2026, 9, 20),
          DateTime.utc(2026, 9, 20),
        ),
        now: DateTime(2026, 9, 20, 11),
        settings: const ReminderSettings(maxPending: 500),
      );
      final screening = plan.where(
        (r) =>
            r.ruleId == 'newborn-screening' &&
            r.kind == ReminderKind.windowOpens,
      );
      expect(screening.map((r) => r.fireAt), [DateTime(2026, 9, 21, 9)]);
      expect(screening.single.leadTime, Duration.zero);
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

  /// What the "later" button on a notification leaves behind.
  ///
  /// The service writes the day and hands it to the planner; everything
  /// about which reminders survive that is decided here, and until now only
  /// the service's own tests went anywhere near it.
  group('put off until a day', () {
    final occurrences = scheduleFor(
      DateTime.utc(2026, 1, 15),
      DateTime.utc(2026, 9, 20),
    );
    final now = DateTime(2026, 9, 20, 8);
    final u9 = occurrences.firstWhere((o) => o.rule.id == 'u9');

    List<PlannedReminder> planWith(
      Map<String, DateTime> putOff, {
      ReminderSettings settings = const ReminderSettings(maxPending: 500),
    }) => planReminders(
      occurrences: occurrences,
      now: now,
      settings: settings,
      putOff: putOff,
    );

    test('takes the place of every lead that appointment would get', () {
      final usual = planWith(const {}).where((r) => r.ruleId == 'u9');
      expect(
        usual,
        hasLength(greaterThan(1)),
        reason: 'the test is worth nothing if there was only ever one',
      );

      final after = planWith({
        u9.key: DateTime.utc(2026, 9, 25),
      }).where((r) => r.ruleId == 'u9');
      expect(after, hasLength(1));
      expect(after.single.fireAt, DateTime(2026, 9, 25, 9));
      expect(after.single.leadTime, Duration.zero);
      expect(after.single.kind, ReminderKind.windowOpens);
    });

    test('at the hour the person asked to be reminded at', () {
      final plan = planWith(
        {u9.key: DateTime.utc(2026, 9, 25)},
        settings: const ReminderSettings(hour: 18, minute: 45, maxPending: 500),
      ).where((r) => r.ruleId == 'u9');
      expect(plan.single.fireAt, DateTime(2026, 9, 25, 18, 45));
    });

    test('leaves every other appointment where it was', () {
      final before = planWith(const {}).where((r) => r.ruleId != 'u9');
      final after = planWith({
        u9.key: DateTime.utc(2026, 9, 25),
      }).where((r) => r.ruleId != 'u9');
      expect(
        after.map((r) => '${r.id}/${r.fireAt}'),
        before.map((r) => '${r.id}/${r.fireAt}'),
      );
    });

    test('a day that has already passed counts for nothing', () {
      // The service drops a stale row when it reschedules, but the planner
      // is handed whatever it is handed and has to mean the same thing.
      final after = planWith({
        u9.key: DateTime.utc(2026, 9, 10),
      }).where((r) => r.ruleId == 'u9');
      expect(after, hasLength(greaterThan(1)), reason: 'the leads are back');
    });

    test('a deadline warning is put off with the rest', () {
      // Putting off is about the appointment, not about one of the three
      // ways it was announced: the person asked not to hear about it again
      // until Friday.
      final withDeadline = occurrences.firstWhere(
        (o) => o.isOpen && o.deadline != null,
      );
      expect(
        planWith(const {}).where((r) => r.occurrenceKey == withDeadline.key),
        contains(
          isA<PlannedReminder>().having(
            (r) => r.kind,
            'kind',
            ReminderKind.deadlineApproaching,
          ),
        ),
      );

      final after = planWith({
        withDeadline.key: DateTime.utc(2026, 9, 25),
      }).where((r) => r.occurrenceKey == withDeadline.key);
      expect(after, hasLength(1));
      expect(after.single.kind, ReminderKind.windowOpens);
    });

    test('an appointment that is settled is not reminded about anyway', () {
      final settled = computeOccurrences(
        person: Person(
          id: 'p1',
          name: 'Kind',
          dateOfBirth: DateTime.utc(2026, 1, 15),
        ),
        catalogs: catalogs,
        completions: [
          Completion(
            personId: 'p1',
            ruleId: 'u9',
            completedOn: DateTime.utc(2026, 9, 19),
          ),
        ],
        today: DateTime.utc(2026, 9, 20),
      );
      final plan = planReminders(
        occurrences: settled,
        now: now,
        settings: const ReminderSettings(maxPending: 500),
        putOff: {'p1-u9': DateTime.utc(2026, 9, 25)},
      );
      expect(plan.where((r) => r.ruleId == 'u9'), isEmpty);
    });

    test('a key that matches nothing changes nothing', () {
      expect(
        planWith({'nobody-at-all': DateTime.utc(2026, 9, 25)}).map((r) => r.id),
        planWith(const {}).map((r) => r.id),
      );
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

  group('the payload a notification carries', () {
    /// What the app taps into is a string the operating system kept while
    /// the app was not running, possibly written by a version that has since
    /// been replaced. It has to survive the round trip and it has to be
    /// refused rather than trusted when it did not come from here.
    final plan = planReminders(
      occurrences: scheduleFor(
        DateTime.utc(2026, 1, 15),
        DateTime.utc(2026, 9, 20),
      ),
      now: DateTime(2026, 9, 20, 8),
      settings: const ReminderSettings(maxPending: 500),
    );

    test('comes back out of its own encoding unchanged', () {
      for (final reminder in plan) {
        final there = ReminderPayload.of(reminder);
        final back = ReminderPayload.tryParse(there.encode());
        expect(back, isNotNull, reason: reminder.occurrenceKey);
        expect(back!.occurrenceKey, there.occurrenceKey);
        expect(back.personId, there.personId);
        expect(back.ruleId, there.ruleId);
        expect(back.doseId, there.doseId);
      }
    });

    test('a dose is carried along, and its absence is not invented', () {
      const withDose = ReminderPayload(
        occurrenceKey: 'p1-mmr#2',
        personId: 'p1',
        ruleId: 'mmr',
        doseId: '2',
      );
      expect(ReminderPayload.tryParse(withDose.encode())!.doseId, '2');

      const without = ReminderPayload(
        occurrenceKey: 'p1-u9',
        personId: 'p1',
        ruleId: 'u9',
      );
      expect(without.encode(), isNot(contains('dose')));
      expect(ReminderPayload.tryParse(without.encode())!.doseId, isNull);
    });

    test('an id that contains the key separator survives', () {
      // The occurrence key is built as "person-rule#dose", and a person id
      // is a uuid today but has not always been one; splitting the key back
      // apart is exactly what this payload exists to avoid.
      const payload = ReminderPayload(
        occurrenceKey: 'a-b#c-d-u9',
        personId: 'a-b#c-d',
        ruleId: 'u9',
      );
      final back = ReminderPayload.tryParse(payload.encode())!;
      expect(back.personId, 'a-b#c-d');
      expect(back.ruleId, 'u9');
    });

    test('anything that is not one of ours is refused', () {
      for (final raw in <String?>[
        null,
        '',
        'not json',
        '[]',
        '17',
        '"just a string"',
        '{}',
        '{"key":"k","person":"p"}',
        '{"key":"k","person":"p","rule":null}',
        '{"key":1,"person":"p","rule":"r"}',
      ]) {
        expect(ReminderPayload.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('a dose that is not a string is dropped rather than fatal', () {
      final payload = ReminderPayload.tryParse(
        '{"key":"k","person":"p","rule":"r","dose":7}',
      );
      expect(payload, isNotNull);
      expect(payload!.doseId, isNull);
    });
  });
}
