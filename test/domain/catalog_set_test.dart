import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/localized_text.dart';

import '../support/catalogs.dart';

/// What every shipped catalog has to satisfy, whatever it is about. The
/// sourcing promise the app makes is only worth something if it is enforced
/// here rather than checked by hand.
void main() {
  final set = shippedCatalogs();

  test('all four catalogs ship', () {
    expect(set.catalogs.map((c) => c.id), [
      'children',
      'vaccinations',
      'dental',
      'adults',
    ]);
  });

  test('every rule names a resolvable source with an as-of date', () {
    for (final rule in set.rules) {
      expect(rule.source.url, startsWith('https://'), reason: rule.id);
      expect(
        rule.source.asOf.year,
        greaterThanOrEqualTo(2020),
        reason: rule.id,
      );
    }
  });

  test('every rule and every source reads in both languages', () {
    for (final rule in set.rules) {
      for (final locale in LocalizedText.supportedLocales) {
        expect(rule.title(locale), isNotEmpty, reason: '${rule.id}/$locale');
        expect(
          rule.description(locale),
          isNotEmpty,
          reason: '${rule.id}/$locale',
        );
        expect(
          rule.source.name(locale),
          isNotEmpty,
          reason: '${rule.source.id}/$locale',
        );
      }
    }
  });

  test('rule ids are unique across catalogs', () {
    // They have to be: an occurrence key is person plus rule id, so two rules
    // sharing an id would share a completion and a notification.
    final ids = set.rules.map((r) => r.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('the German text is really German', () {
    for (final rule in set.rules) {
      expect(
        rule.description('de'),
        isNot(equals(rule.description('en'))),
        reason: rule.id,
      );
    }
  });
}
