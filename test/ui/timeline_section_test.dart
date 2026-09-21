import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/ui/timeline_screen.dart';

import '../support/catalogs.dart';

void main() {
  final today = DateTime.utc(2026, 9, 21);
  final occurrences = computeOccurrences(
    person: Person(id: 'p1', name: 'Mila', dateOfBirth: today),
    catalogs: CatalogSet([childrenCatalog()]),
    completions: const [],
    today: today,
  );
  Occurrence exam(String id) => occurrences.singleWhere((o) => o.rule.id == id);

  test('what starts within five years is coming up', () {
    expect(sectionOf(exam('u9'), today), TimelineSection.comingUp);
  });

  test('what starts later is set apart', () {
    expect(sectionOf(exam('j1'), today), TimelineSection.farAhead);
  });

  test('the boundary is the day five years from today', () {
    final base = exam('u9');
    Occurrence at(DateTime start) => Occurrence(
      personId: base.personId,
      rule: base.rule,
      windowStart: start,
      status: OccurrenceStatus.upcoming,
    );
    expect(
      sectionOf(at(DateTime.utc(2031, 9, 21)), today),
      TimelineSection.comingUp,
    );
    expect(
      sectionOf(at(DateTime.utc(2031, 9, 22)), today),
      TimelineSection.farAhead,
    );
  });

  test('the other groups do not depend on the distance', () {
    expect(sectionOf(exam('u1'), today), TimelineSection.needsAttention);
  });
}
