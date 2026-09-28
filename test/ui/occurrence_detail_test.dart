import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/l10n/app_localizations_en.dart';

import '../support/catalogs.dart';
import '../support/harness.dart';

/// The appointment page in the states the walk through the app never
/// reaches.
///
/// Each of these is a line the person reads to decide whether to bother: a
/// lapsed entitlement, a date that is only a guess, something the insurer
/// may not pay for. They are one `if` each in the build method, which is
/// exactly the kind of thing that survives a refactor by disappearing.
void main() {
  final l10n = AppLocalizationsEn();
  final catalogs = shippedCatalogs();

  /// Eight years old: past the U9 and its catch-up limit, inside the U10,
  /// and part way through a vaccination series.
  final child = Person(
    id: 'jon',
    name: 'Jon',
    dateOfBirth: DateTime.utc(2018, 5, 10),
  );

  List<Occurrence> timeline([Person? person]) => computeOccurrences(
    person: person ?? child,
    catalogs: catalogs,
    completions: const [],
    today: pinnedToday,
  );

  Future<void> open(WidgetTester tester, Occurrence occurrence) async {
    await tester.tap(find.text(child.name));
    await settle(tester);
    final entry = find.byKey(Key('occurrence-${occurrence.key}'));
    await scrollTo(tester, entry);
    // scrollTo stops as soon as the row is built, which for one far down a
    // long timeline can still be below the fold.
    await tester.ensureVisible(entry);
    await settle(tester);
    await tester.tap(entry);
    await settle(tester);
  }

  appTest(
    'a lapsed entitlement says so instead of naming a date',
    people: [child],
    (tester, db) async {
      final lapsed = timeline().firstWhere(
        (o) => o.status == OccurrenceStatus.expired && o.deadline != null,
      );
      await open(tester, lapsed);

      expect(find.text(l10n.deadlinePassed(lapsed.deadline!)), findsOneWidget);
      expect(
        find.text(l10n.deadlineLabel),
        findsNothing,
        reason: 'a lapsed entitlement has nothing left to catch up by',
      );
    },
  );

  appTest('one still open names the day to catch up by', people: [child], (
    tester,
    db,
  ) async {
    final open_ = timeline().firstWhere((o) => o.isOpen && o.deadline != null);
    await open(tester, open_);

    expect(find.text(l10n.deadlineLabel), findsOneWidget);
    expect(find.text(l10n.deadlinePassed(open_.deadline!)), findsNothing);
  });

  appTest('what the insurer may not pay for is marked', people: [child], (
    tester,
    db,
  ) async {
    final extra = timeline().firstWhere((o) => !o.rule.statutory && o.isOpen);
    await open(tester, extra);

    expect(find.text(l10n.notStatutory), findsOneWidget);
  });

  appTest(
    'a date that waits on the dose before it is called provisional',
    people: [child],
    (tester, db) async {
      final guessed = timeline().firstWhere((o) => o.provisional);
      await open(tester, guessed);

      expect(find.text(l10n.provisional), findsOneWidget);
    },
  );

  appTest(
    'a statutory appointment carries no insurer warning',
    people: [child],
    (tester, db) async {
      final statutory = timeline().firstWhere(
        (o) => o.rule.statutory && o.isOpen && !o.provisional,
      );
      await open(tester, statutory);

      expect(find.text(l10n.notStatutory), findsNothing);
      expect(find.text(l10n.provisional), findsNothing);
    },
  );

  appTest(
    'recording an appointment puts the day on the page',
    people: [child],
    (tester, db) async {
      final target = timeline().firstWhere(
        (o) => o.isOpen && o.deadline == null && !o.provisional,
      );
      await open(tester, target);

      await scrollTo(tester, find.byKey(const Key('mark-done')));
      await tester.tap(find.byKey(const Key('mark-done')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('date-input')), '09202026');
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await settle(tester);

      await scrollTo(tester, find.text(l10n.completedOnLabel(pinnedToday)));
      expect(find.text(l10n.completedOnLabel(pinnedToday)), findsOneWidget);
    },
  );
}
