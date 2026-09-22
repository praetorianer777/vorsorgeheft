import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/domain/own_appointment.dart';
import 'package:vorsorgeheft/sync/hlc.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';

import 'generated/schema.dart';
import 'generated/schema_v2.dart' as v2;

/// Every schema version drift has ever created for this app is recorded under
/// drift_schemas/, and run-tests.sh refuses a database.dart that no longer
/// matches the newest dump. What is checked here is the other half: that the
/// migration from each older version ends in exactly the schema a fresh
/// install gets, and that the data a released version wrote survives it.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const current = 5;

  for (final from in GeneratedHelper.versions.where((v) => v < current)) {
    test('a version $from database migrates to the current schema', () async {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, current);
    });
  }

  test('what v0.1.0 wrote is still there after the upgrade', () async {
    // v0.1.0 shipped schema 2. The rows are written the way that version
    // wrote them - dates as ISO-8601 text, the shared key as base64 - so a
    // change to the storage format would fail here rather than on a phone.
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old.customStatement('''
      INSERT INTO persons VALUES
        ('mila', 'Mila', '2026-09-01T00:00:00.000Z', 0, NULL),
        ('sara', 'Sara', '1988-06-30T00:00:00.000Z', 2, 'allergic to penicillin');
      INSERT INTO completions VALUES
        ('mila', 'u2', '', '2026-09-05T00:00:00.000Z', 0, 'Dr. Weber'),
        ('sara', 'td-booster', '', '2026-03-15T00:00:00.000Z', 0, NULL),
        ('mila', 'six-in-one', '1', '2026-11-02T00:00:00.000Z', 1, NULL);
      INSERT INTO settings VALUES
        ('locale', 'de'),
        ('node-id', 'phone-2026'),
        ('sync.private-key', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        ('support.prompt.dismissed', 'true');
      INSERT INTO changes VALUES
        ('person', 'mila', 'name', '1758000000000-0000-phone-2026', '"Mila"'),
        ('person', 'mila', 'dateOfBirth', '1758000000000-0001-phone-2026',
          '"2026-09-01T00:00:00.000Z"'),
        ('completion', 'sara|td-booster|', 'completedOn',
          '1758000001000-0000-phone-2026', '"2026-03-15T00:00:00.000Z"');
      INSERT INTO peers VALUES
        ('other-phone', 'Pixel 8', 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          '1758000001000-0000-phone-2026', '2026-09-21T10:00:00.000Z');
    ''');
    await old.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, current);

    final people = await db.allPersons();
    expect(people.map((p) => p.name), ['Sara', 'Mila']);
    expect(people.first.dateOfBirth, DateTime.utc(1988, 6, 30));
    expect(people.first.notes, 'allergic to penicillin');
    expect(people.first.optionalRules, isEmpty);
    // The table that arrived with schema 5 is empty but usable.
    expect(await db.allOwnAppointments(), isEmpty);
    await db.upsertOwnAppointment(
      OwnAppointment(
        id: 'eyes',
        personId: 'sara',
        title: 'Eye check',
        firstOn: DateTime.utc(2026, 11, 3),
        everyMonths: 12,
      ),
    );
    expect((await db.allOwnAppointments()).single.title, 'Eye check');
    expect(people.last.dateOfBirth, DateTime.utc(2026, 9, 1));

    final completions = await db.allCompletions();
    expect(completions, hasLength(3));
    final dose = completions.singleWhere((c) => c.ruleId == 'six-in-one');
    expect(dose.doseId, '1');
    expect(dose.skipped, isTrue);
    expect(completions.singleWhere((c) => c.ruleId == 'u2').note, 'Dr. Weber');

    expect(await db.settingValue('locale'), 'de');
    expect(await db.settingValue('support.prompt.dismissed'), 'true');
    expect(await db.privateKey(), List<int>.filled(32, 0));

    final peer = (await db.allPeers()).single;
    expect(peer.deviceName, 'Pixel 8');
    expect(peer.sharedKey, List<int>.filled(32, 1));
    expect(peer.lastSyncHlc, Hlc.parse('1758000001000-0000-phone-2026'));
    expect(peer.lastSyncAt, DateTime.utc(2026, 9, 21, 10));

    expect(await db.changesSince(Hlc.zero('')), hasLength(3));
    expect(await db.familyName('family'), isNull);

    // The store picks its node id and clock up from what was there, so the
    // next write on the upgraded phone still sorts after the old ones.
    final store = await ReplicatedStore.open(db);
    expect(store.nodeId, 'phone-2026');
    final latest = await store.latest;
    expect(latest, Hlc.parse('1758000001000-0000-phone-2026'));
  });

  test('the migration does not recreate tables', () async {
    // Recreating a table is how data gets lost in a migration: the row count
    // after the upgrade has to be the row count before it, and the persons
    // table must still enforce its foreign key once the database is open.
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old.customStatement('''
      INSERT INTO persons VALUES ('a', 'A', '2020-01-01T00:00:00.000Z', 0, NULL);
      INSERT INTO completions VALUES ('a', 'u1', '', '2020-01-02T00:00:00.000Z', 0, NULL);
    ''');
    await old.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, current);
    expect(await db.allCompletions(), hasLength(1));
    await db.deletePerson('a');
    expect(await db.allCompletions(), isEmpty);
  });
}
