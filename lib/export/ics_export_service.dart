import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/catalog_repository.dart';
import '../data/database.dart';
import '../domain/occurrence.dart';
import '../domain/person.dart';
import '../domain/schedule_engine.dart';
import 'schedule_export.dart';
import 'share_gateway.dart';

/// Writes the computed schedule to an .ics file and offers it for sharing.
class IcsExportService {
  IcsExportService({
    required AppDatabase database,
    required CatalogRepository catalogs,
    required ShareGateway share,
    required DateTime Function() clock,
    Future<Directory> Function()? directory,
  }) : _db = database,
       _catalogs = catalogs,
       _share = share,
       _clock = clock,
       _directory = directory ?? getTemporaryDirectory;

  /// Where the sequence numbers of earlier exports live. Device-local on
  /// purpose: it describes what this phone has already written into someone's
  /// calendar, which is not a fact about the family.
  static const recordsKey = 'ics.export.records';

  final AppDatabase _db;
  final CatalogRepository _catalogs;
  final ShareGateway _share;
  final DateTime Function() _clock;
  final Future<Directory> Function() _directory;

  /// Exports one person, or the whole family when [personId] is null.
  Future<File> export({
    String? personId,
    required String locale,
    required IcsTexts texts,
  }) async {
    final all = await _db.allPersons();
    final people = personId == null
        ? all
        : all.where((person) => person.id == personId).toList();
    final completions = await _db.allCompletions();
    final catalogs = await _catalogs.load();
    final now = _clock();
    final today = DateTime.utc(now.year, now.month, now.day);

    final occurrences = <Occurrence>[
      for (final person in people)
        ...computeOccurrences(
          person: person,
          catalogs: catalogs,
          completions: completions,
          today: today,
        ),
    ];

    final export = buildIcsExport(
      people: people,
      occurrences: occurrences,
      locale: locale,
      stamp: now,
      texts: texts,
      previous: await _records(),
    );
    await _db.putSetting(recordsKey, _encode(export.records));

    final file = File(
      p.join((await _directory()).path, _fileName(personId, people)),
    );
    await file.writeAsString(export.content);
    return file;
  }

  Future<void> shareExport(File file, {required String subject}) =>
      _share.shareFile(file, subject: subject);

  Future<Map<String, IcsExportRecord>> _records() async {
    final stored = await _db.settingValue(recordsKey);
    if (stored == null) return const {};
    final decoded = jsonDecode(stored);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        entry.key as String: IcsExportRecord(
          fingerprint: (entry.value as Map)['fingerprint'] as String,
          sequence: (entry.value as Map)['sequence'] as int,
        ),
    };
  }

  String _encode(Map<String, IcsExportRecord> records) => jsonEncode({
    for (final entry in records.entries)
      entry.key: {
        'fingerprint': entry.value.fingerprint,
        'sequence': entry.value.sequence,
      },
  });
}

String _fileName(String? personId, List<Person> people) {
  if (personId == null || people.isEmpty) return 'vorsorge-family.ics';
  return 'vorsorge-${_slug(people.first.name)}.ics';
}

/// A share sheet passes the name to whatever app receives it, so it stays
/// within what every file system and mail client accepts.
String _slug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'person' : slug;
}
