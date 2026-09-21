import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/catalog.dart';
import 'package:vorsorgereminder/domain/schedule.dart';

const _source = {
  'name': {'en': 'G-BA children guideline', 'de': 'G-BA Kinder-Richtlinie'},
  'url': 'https://www.g-ba.de/richtlinien/15/',
  'asOf': '2026-09-20',
};

Map<String, Object?> catalogWith({
  Map<String, Object?>? rule,
  Map<String, Object?>? sources,
}) => {
  'catalogId': 'children',
  'catalogVersion': '2026.09',
  'name': {'en': "Children's check-ups", 'de': 'Kindervorsorge'},
  'sources': sources ?? {'gba-kinder-rl': _source},
  'rules': [
    rule ??
        {
          'id': 'u6',
          'title': {'en': 'U6', 'de': 'U6'},
          'description': {'en': 'Check-up', 'de': 'Untersuchung'},
          'source': 'gba-kinder-rl',
          'schedule': {
            'type': 'ageWindow',
            'from': {'months': 9},
            'to': {'months': 12},
            'toleranceTo': {'months': 14},
            'hardDeadline': true,
          },
        },
  ],
};

Matcher throwsCatalogError(String fragment) => throwsA(
  isA<CatalogFormatException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  test('parses a well-formed catalog', () {
    final catalog = Catalog.fromJson(catalogWith());
    expect(catalog.id, 'children');
    expect(catalog.version, '2026.09');
    expect(catalog.rules, hasLength(1));

    final rule = catalog.rules.single;
    expect(rule.title('de'), 'U6');
    expect(rule.statutory, isTrue);
    expect(rule.optional, isFalse);
    expect(rule.source.url, startsWith('https://'));
    expect(rule.source.asOf, DateTime.utc(2026, 9, 20));

    final schedule = rule.schedule as AgeWindow;
    expect(schedule.hardDeadline, isTrue);
    expect(schedule.toleranceTo?.months, 14);
  });

  group('sourcing is enforced, not merely expected', () {
    test('a rule without a source is rejected', () {
      final rule = Map<String, Object?>.from(
        (catalogWith()['rules'] as List).single as Map,
      )..remove('source');
      expect(
        () => Catalog.fromJson(catalogWith(rule: rule)),
        throwsCatalogError('"source" is required'),
      );
    });

    test('a source that does not resolve is rejected, naming the rule', () {
      final rule = Map<String, Object?>.from(
        (catalogWith()['rules'] as List).single as Map,
      )..['source'] = 'nope';
      expect(
        () => Catalog.fromJson(catalogWith(rule: rule)),
        throwsCatalogError('rule "u6"'),
      );
      expect(
        () => Catalog.fromJson(catalogWith(rule: rule)),
        throwsCatalogError('does not resolve'),
      );
    });

    test('a source without an as-of date is rejected', () {
      final source = Map<String, Object?>.from(_source)..remove('asOf');
      expect(
        () => Catalog.fromJson(catalogWith(sources: {'gba-kinder-rl': source})),
        throwsCatalogError('"asOf"'),
      );
    });

    test('a source url that is not https is rejected', () {
      final source = Map<String, Object?>.from(_source)
        ..['url'] = 'http://example.org';
      expect(
        () => Catalog.fromJson(catalogWith(sources: {'gba-kinder-rl': source})),
        throwsCatalogError('https'),
      );
    });
  });

  group('translations are enforced', () {
    test('a rule missing a German title is rejected', () {
      final rule = Map<String, Object?>.from(
        (catalogWith()['rules'] as List).single as Map,
      )..['title'] = {'en': 'U6'};
      expect(
        () => Catalog.fromJson(catalogWith(rule: rule)),
        throwsCatalogError('missing "de"'),
      );
    });

    test('an empty translation counts as missing', () {
      final rule = Map<String, Object?>.from(
        (catalogWith()['rules'] as List).single as Map,
      )..['description'] = {'en': 'Check-up', 'de': '   '};
      expect(
        () => Catalog.fromJson(catalogWith(rule: rule)),
        throwsCatalogError('"de"'),
      );
    });
  });

  group('schedules are validated', () {
    Map<String, Object?> ruleWithSchedule(Map<String, Object?> schedule) =>
        Map<String, Object?>.from(
          (catalogWith()['rules'] as List).single as Map,
        )..['schedule'] = schedule;

    test('an unknown schedule type is rejected, naming the rule', () {
      expect(
        () => Catalog.fromJson(
          catalogWith(rule: ruleWithSchedule({'type': 'whenever'})),
        ),
        throwsCatalogError('rule "u6": unknown schedule type "whenever"'),
      );
    });

    test('a hard deadline without a tolerance limit is rejected', () {
      expect(
        () => Catalog.fromJson(
          catalogWith(
            rule: ruleWithSchedule({
              'type': 'ageWindow',
              'from': {'months': 9},
              'to': {'months': 12},
              'hardDeadline': true,
            }),
          ),
        ),
        throwsCatalogError('needs a "toleranceTo"'),
      );
    });

    test('a missing window bound is rejected', () {
      expect(
        () => Catalog.fromJson(
          catalogWith(
            rule: ruleWithSchedule({
              'type': 'ageWindow',
              'from': {'months': 9},
            }),
          ),
        ),
        throwsCatalogError('"schedule.to" is required'),
      );
    });

    test('duplicate dose ids within a series are rejected', () {
      expect(
        () => Catalog.fromJson(
          catalogWith(
            rule: ruleWithSchedule({
              'type': 'series',
              'doses': [
                {
                  'id': '1',
                  'from': {'months': 2},
                },
                {
                  'id': '1',
                  'from': {'months': 4},
                },
              ],
            }),
          ),
        ),
        throwsCatalogError('dose ids must be unique'),
      );
    });
  });

  test('duplicate rule ids within a catalog are rejected', () {
    final json = catalogWith();
    json['rules'] = [
      (json['rules'] as List).single,
      (json['rules'] as List).single,
    ];
    expect(
      () => Catalog.fromJson(json),
      throwsCatalogError('rule ids must be unique'),
    );
  });

  test('invalid JSON is reported as such', () {
    expect(
      () => Catalog.parse('{not json'),
      throwsCatalogError('invalid JSON'),
    );
  });

  test('parse accepts the same document as fromJson', () {
    final catalog = Catalog.parse(jsonEncode(catalogWith()));
    expect(catalog.rules.single.id, 'u6');
  });

  group('retiredOn', () {
    test('is parsed as a UTC date', () {
      final json = catalogWith();
      ((json['rules'] as List).single as Map)['retiredOn'] = '2027-01-01';
      expect(
        Catalog.fromJson(json).rules.single.retiredOn,
        DateTime.utc(2027, 1, 1),
      );
    });

    test('is absent by default', () {
      expect(Catalog.fromJson(catalogWith()).rules.single.retiredOn, isNull);
    });

    test('must be a plain ISO date, naming the rule', () {
      for (final bad in ['01.01.2027', '2027-1-1', 20270101, '2027-02-30']) {
        final json = catalogWith();
        ((json['rules'] as List).single as Map)['retiredOn'] = bad;
        expect(
          () => Catalog.fromJson(json),
          throwsCatalogError('rule "u6": "retiredOn"'),
          reason: '$bad',
        );
      }
    });
  });

  group('_changes', () {
    test('are read oldest first, and the current edition is the latest', () {
      final json = catalogWith();
      json['_changes'] = [
        {'version': '2026.06', 'en': 'First edition.', 'de': 'Erste Ausgabe.'},
        {'version': '2026.09', 'en': 'U7a added.', 'de': 'U7a ergänzt.'},
      ];
      final catalog = Catalog.fromJson(json);
      expect(catalog.changes.map((c) => c.version), ['2026.06', '2026.09']);
      expect(catalog.latestChange?.note('de'), 'U7a ergänzt.');
    });

    test('fall back to the last note when none names the edition', () {
      final json = catalogWith();
      json['_changes'] = [
        {'version': '2026.06', 'en': 'First edition.', 'de': 'Erste Ausgabe.'},
      ];
      expect(Catalog.fromJson(json).latestChange?.version, '2026.06');
    });

    test('are optional', () {
      final catalog = Catalog.fromJson(catalogWith());
      expect(catalog.changes, isEmpty);
      expect(catalog.latestChange, isNull);
    });

    test('need a version and both languages', () {
      final json = catalogWith();
      json['_changes'] = [
        {'en': 'First edition.', 'de': 'Erste Ausgabe.'},
      ];
      expect(
        () => Catalog.fromJson(json),
        throwsCatalogError('"_changes" entry needs a "version"'),
      );
      json['_changes'] = [
        {'version': '2026.09', 'en': 'First edition.'},
      ];
      expect(
        () => Catalog.fromJson(json),
        throwsCatalogError('"_changes" entry for "2026.09": missing "de"'),
      );
    });
  });
}
