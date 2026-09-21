import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/schedule.dart';

import '../support/catalogs.dart';

const _ledgerPath = 'tools/catalog-rule-ledger.json';

/// Recorded appointments are keyed by rule id and dose id, so an id that
/// disappears from a catalog orphans every entry recorded under it. The ledger
/// remembers every id that ever shipped, and this test holds the catalogs to
/// it: nothing may vanish, and nothing new may slip in unrecorded.
void main() {
  final ledger =
      ((jsonDecode(File(_ledgerPath).readAsStringSync())
                  as Map<String, Object?>)['catalogs']
              as Map<String, Object?>)
          .map(
            (catalogId, rules) => MapEntry(
              catalogId,
              (rules as Map<String, Object?>).map(
                (ruleId, doses) =>
                    MapEntry(ruleId, (doses as List).cast<String>()),
              ),
            ),
          );
  final shipped = {for (final c in shippedCatalogs().catalogs) c.id: c};

  List<String> dosesOf(String catalogId, String ruleId) {
    final schedule = shipped[catalogId]?.ruleById(ruleId)?.schedule;
    return schedule is Series ? [for (final d in schedule.doses) d.id] : [];
  }

  test('every id the ledger knows is still in its catalog, unchanged', () {
    for (final entry in ledger.entries) {
      final catalog = shipped[entry.key];
      expect(
        catalog,
        isNotNull,
        reason:
            'Catalog "${entry.key}" is in $_ledgerPath but no longer ships. '
            'Catalogs are never removed: retire their rules with "retiredOn".',
      );
      for (final rule in entry.value.entries) {
        expect(
          catalog!.ruleById(rule.key),
          isNotNull,
          reason:
              'Rule "${entry.key}/${rule.key}" is in $_ledgerPath but not in '
              'assets/catalogs/${entry.key}.json. Rules are never renamed or '
              'removed, because recorded appointments are keyed by their id. '
              'Keep the rule and retire it with "retiredOn": "<yyyy-mm-dd>" '
              'instead.',
        );
        expect(
          dosesOf(entry.key, rule.key),
          rule.value,
          reason:
              'The doses of "${entry.key}/${rule.key}" differ from '
              '$_ledgerPath. Dose ids are never renamed or removed, because '
              'recorded doses are keyed by them. Retire the rule with '
              '"retiredOn" and add a new one instead.',
        );
      }
    }
  });

  test('every id a catalog carries is in the ledger', () {
    for (final catalog in shipped.values) {
      expect(
        ledger,
        contains(catalog.id),
        reason:
            'Catalog "${catalog.id}" is not in $_ledgerPath. Add it there: '
            'the ledger records every id that ever shipped.',
      );
      for (final rule in catalog.rules) {
        expect(
          ledger[catalog.id],
          contains(rule.id),
          reason:
              'Rule "${catalog.id}/${rule.id}" is not in $_ledgerPath. Add it '
              'there with its dose ids: the ledger records every id that ever '
              'shipped, so adding a rule is a deliberate two-file change.',
        );
      }
    }
  });
}
