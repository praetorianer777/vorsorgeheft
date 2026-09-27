import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

/// What has to hold for every person the app can be given, rather than for
/// the ages the matrix spells out.
///
/// The matrix is worth a lot when a rule is added and nothing when one is
/// quietly edited into nonsense: it only knows the ages it lists. This walks
/// hundreds of birth dates through every catalog and asserts the handful of
/// things that must be true whatever the guidelines say - which is exactly
/// what a careless edit breaks.
void main() {
  final catalogs = shippedCatalogs();
  final today = DateTime.utc(2026, 9, 22);

  /// The same set every run: a failure has to be reproducible, and a random
  /// seed that changes nightly turns a real fault into a rumour.
  final random = Random(20260922);

  /// A century of birth dates, from a newborn to a hundred years old, plus
  /// the edges that catch off-by-one: born today, born on a leap day, born
  /// on new year's eve.
  final births = <DateTime>[
    today,
    DateTime.utc(2024, 2, 29),
    DateTime.utc(2025, 12, 31),
    DateTime.utc(1926, 9, 22),
    for (var i = 0; i < 300; i++)
      DateTime.utc(
        today.year - random.nextInt(100),
        1 + random.nextInt(12),
        1 + random.nextInt(28),
      ),
  ];

  final people = [
    for (final birth in births)
      for (final sex in [Sex.female, Sex.male, Sex.notStated])
        Person(
          id: 'p-${birth.toIso8601String()}-${sex.name}',
          name: 'P',
          dateOfBirth: birth,
          sex: sex,
        ),
    for (final birth in births.take(20))
      for (final species in [Species.dog, Species.cat])
        Person(
          id: 'a-${birth.toIso8601String()}-${species.name}',
          name: 'A',
          dateOfBirth: birth,
          species: species,
        ),
  ];

  List<Occurrence> timelineOf(
    Person person, {
    List<Completion> done = const [],
  }) => computeOccurrences(
    person: person,
    catalogs: catalogs,
    completions: done,
    today: today,
  );

  test('nothing is ever due before the person was born', () {
    for (final person in people) {
      for (final occurrence in timelineOf(person)) {
        expect(
          occurrence.windowStart.isBefore(person.dateOfBirth),
          isFalse,
          reason: '${person.id}: ${occurrence.key}',
        );
      }
    }
  });

  test('a window opens before it closes, and the deadline comes last', () {
    for (final person in people) {
      for (final occurrence in timelineOf(person)) {
        final end = occurrence.windowEnd;
        final deadline = occurrence.deadline;
        if (end != null) {
          expect(
            end.isBefore(occurrence.windowStart),
            isFalse,
            reason: '${person.id}: ${occurrence.key}',
          );
        }
        if (deadline != null && end != null) {
          expect(
            deadline.isBefore(end),
            isFalse,
            reason: '${person.id}: ${occurrence.key} lapses before it closes',
          );
        }
      }
    }
  });

  test('the same person computed twice gives the same timeline', () {
    // The screens recompute on every rebuild, and the ICS export keys its
    // events on this order: an engine that shuffles would duplicate events
    // in a calendar rather than update them.
    for (final person in people) {
      final first = timelineOf(person);
      final second = timelineOf(person);
      expect(
        second.map((o) => '${o.key}/${o.status.name}'),
        first.map((o) => '${o.key}/${o.status.name}'),
        reason: person.id,
      );
    }
  });

  test('every appointment on a timeline has its own key', () {
    // Two appointments sharing a key would share their completion, their
    // notification and their calendar event.
    for (final person in people) {
      final keys = timelineOf(person).map((o) => o.key).toList();
      expect(keys.toSet(), hasLength(keys.length), reason: person.id);
    }
  });

  test('a status matches the dates it was derived from', () {
    for (final person in people) {
      for (final occurrence in timelineOf(person)) {
        final end = occurrence.windowEnd;
        switch (occurrence.status) {
          case OccurrenceStatus.upcoming:
            expect(
              occurrence.windowStart.isAfter(today),
              isTrue,
              reason: '${person.id}: ${occurrence.key}',
            );
          case OccurrenceStatus.due:
            expect(
              occurrence.windowStart.isAfter(today),
              isFalse,
              reason: '${person.id}: ${occurrence.key}',
            );
            if (end != null) {
              expect(
                end.isBefore(today),
                isFalse,
                reason: '${person.id}: ${occurrence.key}',
              );
            }
          case OccurrenceStatus.overdue:
            expect(
              end != null && end.isBefore(today),
              isTrue,
              reason: '${person.id}: ${occurrence.key}',
            );
          case OccurrenceStatus.expired:
            expect(
              (occurrence.deadline ?? end)!.isBefore(today),
              isTrue,
              reason: '${person.id}: ${occurrence.key}',
            );
          case OccurrenceStatus.done || OccurrenceStatus.skipped:
            expect(
              occurrence.completedOn,
              isNotNull,
              reason: '${person.id}: ${occurrence.key}',
            );
        }
      }
    }
  });

  test('recording one appointment settles that one and no other', () {
    for (final person in people) {
      final before = timelineOf(person);
      final open = before.where((o) => o.isOpen).toList();
      if (open.isEmpty) continue;
      final target = open[random.nextInt(open.length)];

      final after = timelineOf(
        person,
        done: [
          Completion(
            personId: person.id,
            ruleId: target.rule.id,
            doseId: target.doseId,
            completedOn: today,
          ),
        ],
      );

      // Compared by rule and dose rather than by key: a recurring
      // entitlement is anchored to the date it was last had, so recording
      // one moves its instance id from the date it was due to the date it
      // happened.
      final settled = after
          .where((o) => o.status == OccurrenceStatus.done)
          .map((o) => '${o.rule.id}/${o.doseId}')
          .toList();
      expect(settled, [
        '${target.rule.id}/${target.doseId}',
      ], reason: '${person.id}: ${target.key}');
    }
  });

  test('skipping settles without inventing an appointment', () {
    for (final person in people.take(60)) {
      final before = timelineOf(person);
      final open = before.where((o) => o.isOpen).toList();
      if (open.isEmpty) continue;
      final target = open.first;

      final after = timelineOf(
        person,
        done: [
          Completion(
            personId: person.id,
            ruleId: target.rule.id,
            doseId: target.doseId,
            completedOn: today,
            skipped: true,
          ),
        ],
      );

      expect(
        after
            .where((o) => o.status == OccurrenceStatus.skipped)
            .map((o) => '${o.rule.id}/${o.doseId}'),
        ['${target.rule.id}/${target.doseId}'],
        reason: person.id,
      );
      // A series moves its next dose along when one is recorded, so the keys
      // may differ; what must not happen is the timeline growing every time
      // something is recorded.
      expect(
        after.length,
        lessThanOrEqualTo(before.length + 1),
        reason: person.id,
      );
    }
  });

  test('what has lapsed stays lapsed when something else is recorded', () {
    for (final person in people.take(60)) {
      final before = timelineOf(person);
      final expired = before
          .where((o) => o.status == OccurrenceStatus.expired)
          .map((o) => o.key)
          .toSet();
      if (expired.isEmpty) continue;
      final open = before.where((o) => o.isOpen).toList();
      if (open.isEmpty) continue;

      final after = timelineOf(
        person,
        done: [
          Completion(
            personId: person.id,
            ruleId: open.first.rule.id,
            doseId: open.first.doseId,
            completedOn: today,
          ),
        ],
      );
      final stillExpired = after
          .where((o) => o.status == OccurrenceStatus.expired)
          .map((o) => o.key)
          .toSet();
      expect(stillExpired, containsAll(expired), reason: person.id);
    }
  });

  test('an animal is never given a human catalog, and the other way round', () {
    final human = catalogs.rulesFor(Species.human).map((r) => r.id).toSet();
    for (final person in people) {
      final ids = timelineOf(person).map((o) => o.rule.id).toSet();
      if (person.species == Species.human) {
        expect(ids.difference(human), isEmpty, reason: person.id);
      } else {
        expect(ids.intersection(human), isEmpty, reason: person.id);
      }
    }
  });
}
