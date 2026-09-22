import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/catalog.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/export/schedule_export.dart';

import '../support/catalogs.dart';

final _mila = Person(
  id: 'infant',
  name: 'Mila',
  dateOfBirth: DateTime.utc(2026, 9, 1),
);

final _today = DateTime.utc(2026, 9, 20);
final _stamp = DateTime.utc(2026, 9, 20, 12);

final _texts = IcsTexts(
  calendarName: 'Preventive care – Mila',
  disclaimer:
      'Not medical advice. Entitlements vary between insurers; ask your '
      "doctor's office when in doubt.",
  source: (name, asOf) =>
      'Source: $name · as of ${asOf.toIso8601String().substring(0, 10)}',
  notStatutory: 'Depends on your insurer',
  deadline: (date) =>
      'Catch up by ${date.toIso8601String().substring(0, 10)}; after that the '
      'entitlement lapses.',
  dose: (title, number, total) => '$title · dose $number of $total',
);

IcsExport exportFor({
  List<Completion> completions = const [],
  Map<String, IcsExportRecord> previous = const {},
  DateTime? today,
}) {
  final catalogs = CatalogSet([childrenCatalog()]);
  return buildIcsExport(
    people: [_mila],
    occurrences: computeOccurrences(
      person: _mila,
      catalogs: catalogs,
      completions: completions,
      today: today ?? _today,
    ),
    locale: 'en',
    stamp: _stamp,
    texts: _texts,
    previous: previous,
  );
}

void main() {
  test('matches the golden file', () {
    final golden = File('test/export/golden/mila.ics');
    expect(
      exportFor().content,
      golden.readAsStringSync(),
      reason:
          'Regenerate with: dart run tool/update_ics_golden.dart, and read the '
          'diff before committing it.',
    );
  });

  test('every appointment carries its source and the catalog it came from', () {
    // Long lines are folded at 75 octets; unfold before searching them.
    final ics = exportFor().content.replaceAll('\r\n ', '');
    expect(ics, contains('CATEGORIES:children'));
    expect(ics, contains('G-BA guideline on early detection'));
    expect(ics, contains('URL:https://www.g-ba.de/richtlinien/15/'));
  });

  test('an exclusion deadline is spelled out and warned about twice', () {
    final ics = exportFor().content;
    expect(ics, contains('after that the entitlement lapses'));
    expect(ics.split('TRIGGER;VALUE=DATE-TIME:').length - 1, greaterThan(1));
  });

  test('exporting unchanged data again keeps every uid and sequence', () {
    final first = exportFor();
    final second = exportFor(previous: first.records);

    expect(second.records.keys, first.records.keys);
    expect(
      second.records.values.map((r) => r.sequence),
      everyElement(0),
      reason: 'nothing changed, so no calendar needs to be told about it',
    );
    expect(second.content, first.content);
  });

  test('a recorded appointment raises its sequence and is cancelled', () {
    final first = exportFor();
    final second = exportFor(
      completions: [
        Completion(
          personId: 'infant',
          ruleId: 'u3',
          completedOn: DateTime.utc(2026, 9, 25),
        ),
      ],
      previous: first.records,
    );

    const uid = 'infant-u3@vorsorgereminder';
    expect(second.records[uid]!.sequence, first.records[uid]!.sequence + 1);
    expect(second.content, contains('STATUS:CANCELLED'));
  });

  test('a renamed person raises every sequence and keeps every uid', () {
    // The name is in every summary, so a calendar has to be told about all
    // of the events; the uids stay, or it would add a second set.
    final first = exportFor();
    final renamed = Person(
      id: _mila.id,
      name: 'Mila Vogel',
      dateOfBirth: _mila.dateOfBirth,
    );
    final second = buildIcsExport(
      people: [renamed],
      occurrences: computeOccurrences(
        person: renamed,
        catalogs: CatalogSet([childrenCatalog()]),
        completions: const [],
        today: _today,
      ),
      locale: 'en',
      stamp: _stamp,
      texts: _texts,
      previous: first.records,
    );

    expect(second.records.keys.toSet(), first.records.keys.toSet());
    expect(second.records.values.map((r) => r.sequence), everyElement(1));
    expect(second.content, contains('SUMMARY:Mila Vogel: U6'));
    expect(second.content, isNot(contains('SUMMARY:Mila: U6')));
  });

  test('an appointment never exported is not exported as a cancellation', () {
    // Nothing has been shared yet, so a lapsed entitlement is not in anyone's
    // calendar and writing a cancellation for it would be noise.
    final export = exportFor();
    final lapsed = computeOccurrences(
      person: _mila,
      catalogs: CatalogSet([childrenCatalog()]),
      completions: const [],
      today: _today,
    ).where((o) => o.status == OccurrenceStatus.expired);

    expect(lapsed, isNotEmpty);
    for (final occurrence in lapsed) {
      expect(
        export.records,
        isNot(contains('${occurrence.key}@vorsorgereminder')),
      );
    }
  });

  test('the whole family goes into one file, each event named', () {
    final father = Person(
      id: 'father',
      name: 'Tim',
      dateOfBirth: DateTime.utc(1960, 2, 29),
      sex: Sex.male,
    );
    final catalogs = CatalogSet([childrenCatalog()]);
    final export = buildIcsExport(
      people: [_mila, father],
      occurrences: [
        for (final person in [_mila, father])
          ...computeOccurrences(
            person: person,
            catalogs: catalogs,
            completions: const [],
            today: _today,
          ),
      ],
      locale: 'en',
      stamp: _stamp,
      texts: _texts,
    );

    expect(export.content, contains('SUMMARY:Mila: U6'));
    expect(export.content, isNot(contains('SUMMARY:Tim:')));
  });

  test('the German export carries German catalog text', () {
    final catalogs = CatalogSet([childrenCatalog()]);
    final export = buildIcsExport(
      people: [_mila],
      occurrences: computeOccurrences(
        person: _mila,
        catalogs: catalogs,
        completions: const [],
        today: _today,
      ),
      locale: 'de',
      stamp: _stamp,
      texts: _texts,
    );
    expect(export.content, contains('Lebensmonat'));
  });
}
