import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/catalog_repository.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/export/ics_export_service.dart';
import 'package:vorsorgeheft/export/schedule_export.dart';

import '../support/recording_share.dart';
import '../support/synchronous_assets.dart';

final _texts = IcsTexts(
  calendarName: 'Preventive care',
  disclaimer: 'Not medical advice',
  source: (name, asOf) => 'Source: $name',
  notStatutory: 'Depends on your insurer',
  deadline: (date) => 'Catch up by $date',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('vorsorge-ics'));
  tearDown(() => temp.deleteSync(recursive: true));

  IcsExportService serviceFor(AppDatabase db, RecordingShareGateway share) =>
      IcsExportService(
        database: db,
        catalogs: CatalogRepository(bundle: SynchronousAssetBundle()),
        share: share,
        clock: () => DateTime.utc(2026, 9, 20),
        directory: () async => temp,
      );

  test('an export names the file after the person it covers', () async {
    final db = openInMemoryDatabase();
    await db.upsertPerson(
      Person(
        id: 'infant',
        name: 'Mila Vogel',
        dateOfBirth: DateTime.utc(2026, 9, 1),
      ),
    );
    final share = RecordingShareGateway();
    final service = serviceFor(db, share);

    final file = await service.export(
      personId: 'infant',
      locale: 'en',
      texts: _texts,
    );
    expect(file.path, endsWith('vorsorge-mila-vogel.ics'));
    expect(file.readAsStringSync(), contains('SUMMARY:Mila Vogel: U6'));

    await service.shareExport(file, subject: 'Preventive care');
    expect(share.lastSubject, 'Preventive care');

    await db.close();
  });

  test('a family export covers everyone in one file', () async {
    final db = openInMemoryDatabase();
    await db.upsertPerson(
      Person(id: 'a', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
    );
    await db.upsertPerson(
      Person(id: 'b', name: 'Jonas', dateOfBirth: DateTime.utc(2018, 4, 12)),
    );
    final service = serviceFor(db, RecordingShareGateway());

    final content = (await service.export(
      locale: 'en',
      texts: _texts,
    )).readAsStringSync();

    expect(content, contains('SUMMARY:Mila: U6'));
    expect(content, contains('SUMMARY:Jonas: U10'));

    await db.close();
  });

  test('a second export of unchanged data is byte for byte the same', () async {
    final db = openInMemoryDatabase();
    await db.upsertPerson(
      Person(id: 'a', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
    );
    final service = serviceFor(db, RecordingShareGateway());

    final first = (await service.export(
      locale: 'en',
      texts: _texts,
    )).readAsStringSync();
    final second = (await service.export(
      locale: 'en',
      texts: _texts,
    )).readAsStringSync();

    expect(second, first);
    expect(await db.settingValue(IcsExportService.recordsKey), isNotNull);

    await db.close();
  });

  test('recording an appointment supersedes the event it exported', () async {
    final db = openInMemoryDatabase();
    await db.upsertPerson(
      Person(id: 'a', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
    );
    final service = serviceFor(db, RecordingShareGateway());

    await service.export(locale: 'en', texts: _texts);
    await db.recordCompletion(
      Completion(
        personId: 'a',
        ruleId: 'u3',
        completedOn: DateTime.utc(2026, 9, 25),
      ),
    );
    final content = (await service.export(
      locale: 'en',
      texts: _texts,
    )).readAsStringSync();

    expect(content, contains('UID:a-u3@vorsorgereminder'));
    expect(content, contains('STATUS:CANCELLED'));
    expect(content, contains('SEQUENCE:1'));

    await db.close();
  });
}
