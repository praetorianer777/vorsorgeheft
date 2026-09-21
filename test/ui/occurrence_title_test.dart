import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/l10n/app_localizations.dart';
import 'package:vorsorgeheft/ui/formatting.dart';

import '../support/catalogs.dart';

void main() {
  final birth = DateTime.utc(2026, 1, 15);
  final occurrences = computeOccurrences(
    person: Person(id: 'p1', name: 'Kind', dateOfBirth: birth),
    catalogs: CatalogSet([catalogNamed('vaccinations'), childrenCatalog()]),
    completions: const [],
    today: birth,
  );
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  test('the doses of a series are told apart in both languages', () {
    final second = occurrences.singleWhere(
      (o) => o.rule.id == 'six-in-one' && o.instanceId == 'g2',
    );
    expect(
      occurrenceTitle(en, 'en', second),
      'Six-in-one vaccination · dose 2 of 3',
    );
    expect(
      occurrenceTitle(de, 'de', second),
      'Sechsfachimpfung · 2. Dosis von 3',
    );
  });

  test('a single appointment keeps its plain title', () {
    final u6 = occurrences.singleWhere((o) => o.rule.id == 'u6');
    expect(occurrenceTitle(en, 'en', u6), u6.rule.title('en'));
  });
}
