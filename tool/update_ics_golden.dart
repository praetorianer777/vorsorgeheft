import 'dart:io';

import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/export/schedule_export.dart';

/// Rewrites the golden calendar the export test compares against.
///
/// The golden exists to make a change to the exported format visible in a
/// diff, so this is run deliberately and the diff is read - never as part of
/// the test run itself.
void main() {
  final mila = Person(
    id: 'infant',
    name: 'Mila',
    dateOfBirth: DateTime.utc(2026, 9, 1),
  );
  final catalogs = CatalogSet([
    Catalog.parse(File('assets/catalogs/children.json').readAsStringSync()),
  ]);

  final export = buildIcsExport(
    people: [mila],
    occurrences: computeOccurrences(
      person: mila,
      catalogs: catalogs,
      completions: const [],
      today: DateTime.utc(2026, 9, 20),
    ),
    locale: 'en',
    stamp: DateTime.utc(2026, 9, 20, 12),
    texts: IcsTexts(
      calendarName: 'Preventive care – Mila',
      disclaimer:
          'Not medical advice. Entitlements vary between insurers; ask your '
          "doctor's office when in doubt.",
      source: (name, asOf) =>
          'Source: $name · as of ${asOf.toIso8601String().substring(0, 10)}',
      notStatutory: 'Depends on your insurer',
      deadline: (date) =>
          'Catch up by ${date.toIso8601String().substring(0, 10)}; after that '
          'the entitlement lapses.',
    ),
  );

  File('test/export/golden/mila.ics')
    ..createSync(recursive: true)
    ..writeAsStringSync(export.content);
  stdout.writeln('wrote test/export/golden/mila.ics');
}
