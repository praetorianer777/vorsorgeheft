import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';

import '../support/catalogs.dart';

void main() {
  final birth = DateTime.utc(2026, 1, 15);
  final occurrences = computeOccurrences(
    person: Person(id: 'p1', name: 'Kind', dateOfBirth: birth),
    catalogs: CatalogSet([catalogNamed('vaccinations'), childrenCatalog()]),
    completions: const [],
    today: birth,
  );

  test('a series dose knows its position and the length of the series', () {
    final doses = occurrences
        .where((o) => o.rule.id == 'six-in-one')
        .map((o) => '${o.doseNumber}/${o.doseCount}')
        .toList();
    expect(doses, ['1/3', '2/3', '3/3']);
  });

  test('anything outside a series has no dose', () {
    final u6 = occurrences.singleWhere((o) => o.rule.id == 'u6');
    expect(u6.doseNumber, isNull);
    expect(u6.doseCount, isNull);
  });
}
