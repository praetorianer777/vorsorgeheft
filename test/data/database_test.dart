import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/sync/hlc.dart';
import 'package:vorsorgeheft/sync/sync_protocol.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());

  final anna = Person(
    id: 'anna',
    name: 'Anna',
    dateOfBirth: DateTime.utc(2026, 1, 15),
    sex: Sex.female,
    notes: 'Zwilling',
  );

  test('a person round-trips with every field intact', () async {
    await db.upsertPerson(anna);
    final stored = await db.personById('anna');
    expect(stored!.name, 'Anna');
    expect(stored.dateOfBirth, DateTime.utc(2026, 1, 15));
    expect(stored.sex, Sex.female);
    expect(stored.notes, 'Zwilling');
  });

  test('saving the same id twice edits rather than duplicates', () async {
    await db.upsertPerson(anna);
    await db.upsertPerson(
      Person(id: 'anna', name: 'Anna B.', dateOfBirth: anna.dateOfBirth),
    );
    final all = await db.allPersons();
    expect(all, hasLength(1));
    expect(all.single.name, 'Anna B.');
    expect(all.single.sex, Sex.notStated);
  });

  test('persons come back oldest first', () async {
    await db.upsertPerson(anna);
    await db.upsertPerson(
      Person(id: 'papa', name: 'Papa', dateOfBirth: DateTime.utc(1985, 3, 1)),
    );
    expect((await db.allPersons()).map((p) => p.id), ['papa', 'anna']);
  });

  group('completions', () {
    setUp(() => db.upsertPerson(anna));

    test('round-trip a completion without a dose', () async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      final stored = (await db.allCompletions()).single;
      expect(stored.ruleId, 'u6');
      expect(stored.doseId, isNull);
      expect(stored.skipped, isFalse);
    });

    test('doses of one rule are separate records', () async {
      for (final dose in ['1', '2']) {
        await db.recordCompletion(
          Completion(
            personId: 'anna',
            ruleId: 'sixfold',
            doseId: dose,
            completedOn: DateTime.utc(2026, 3, 1),
          ),
        );
      }
      expect(await db.allCompletions(), hasLength(2));
    });

    test('recording the same appointment twice is an edit', () async {
      for (final date in [
        DateTime.utc(2026, 11, 2),
        DateTime.utc(2026, 11, 9),
      ]) {
        await db.recordCompletion(
          Completion(personId: 'anna', ruleId: 'u6', completedOn: date),
        );
      }
      final all = await db.allCompletions();
      expect(all, hasLength(1));
      expect(all.single.completedOn, DateTime.utc(2026, 11, 9));
    });

    // A null dose id is not equal to anything in SQL, so clearing a completion
    // that has none needs an IS NULL rather than an equality test.
    test('clearing a completion without a dose finds it', () async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      await db.clearCompletion(personId: 'anna', ruleId: 'u6');
      expect(await db.allCompletions(), isEmpty);
    });

    test('clearing one dose leaves the others', () async {
      for (final dose in ['1', '2']) {
        await db.recordCompletion(
          Completion(
            personId: 'anna',
            ruleId: 'sixfold',
            doseId: dose,
            completedOn: DateTime.utc(2026, 3, 1),
          ),
        );
      }
      await db.clearCompletion(
        personId: 'anna',
        ruleId: 'sixfold',
        doseId: '1',
      );
      expect((await db.allCompletions()).single.doseId, '2');
    });

    test('deleting a person takes their completions with them', () async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      await db.deletePerson('anna');
      expect(await db.allPersons(), isEmpty);
      expect(await db.allCompletions(), isEmpty);
    });
  });

  test('settings store and overwrite by key', () async {
    expect(await db.settingValue('locale'), isNull);
    await db.putSetting('locale', 'de');
    await db.putSetting('locale', 'en');
    expect(await db.settingValue('locale'), 'en');
  });

  group('peers', () {
    final bob = Peer(
      nodeId: 'bob',
      deviceName: "Bob's phone",
      sharedKey: List<int>.generate(32, (i) => i),
    );

    test('a peer round-trips with its key', () async {
      await db.savePeer(bob);
      final stored = await db.peer('bob');
      expect(stored!.deviceName, "Bob's phone");
      expect(stored.sharedKey, bob.sharedKey);
      expect(stored.lastSyncHlc, isNull);
      expect(stored.lastSyncAt, isNull);
    });

    test('recording an exchange moves the mark and the time', () async {
      await db.savePeer(bob);
      final mark = Hlc(millis: 5000, counter: 1, nodeId: 'bob');
      await db.recordSync(
        'bob',
        watermark: mark,
        at: DateTime.utc(2026, 9, 20, 8),
      );
      final stored = await db.peer('bob');
      expect(stored!.lastSyncHlc, mark);
      expect(stored.lastSyncAt, DateTime.utc(2026, 9, 20, 8));
    });

    test('removing a peer forgets it', () async {
      await db.savePeer(bob);
      await db.removePeer('bob');
      expect(await db.peer('bob'), isNull);
      expect(await db.allPeers(), isEmpty);
    });

    test('the private key round-trips', () async {
      expect(await db.privateKey(), isNull);
      await db.putPrivateKey(List<int>.generate(32, (i) => 255 - i));
      expect(await db.privateKey(), List<int>.generate(32, (i) => 255 - i));
    });

    test('neither peers nor the private key enter the change log', () async {
      await db.savePeer(bob);
      await db.putPrivateKey(List<int>.filled(32, 7));
      expect(await db.changesSince(Hlc.zero('')), isEmpty);
    });
  });

  test('a version 1 database opens and gains the later tables', () async {
    // The schema exactly as drift created it for version 1, with data in it,
    // so the test fails if the migration ever recreates a table.
    final raw = sqlite3.openInMemory()
      ..execute('''
        CREATE TABLE persons (id TEXT NOT NULL, name TEXT NOT NULL,
          date_of_birth TEXT NOT NULL, sex INTEGER NOT NULL, notes TEXT NULL,
          PRIMARY KEY (id));
        CREATE TABLE completions (
          person_id TEXT NOT NULL REFERENCES persons (id) ON DELETE CASCADE,
          rule_id TEXT NOT NULL, dose_id TEXT NOT NULL DEFAULT '',
          completed_on TEXT NOT NULL,
          skipped INTEGER NOT NULL DEFAULT 0 CHECK (skipped IN (0, 1)),
          note TEXT NULL, PRIMARY KEY (person_id, rule_id, dose_id));
        CREATE TABLE settings (key TEXT NOT NULL, value TEXT NOT NULL,
          PRIMARY KEY (key));
        CREATE TABLE changes (entity TEXT NOT NULL, entity_id TEXT NOT NULL,
          field TEXT NOT NULL, hlc TEXT NOT NULL, value TEXT NOT NULL,
          PRIMARY KEY (entity, entity_id, field));
        INSERT INTO persons VALUES ('anna', 'Anna', '2026-01-15T00:00:00.000Z',
          1, NULL);
        INSERT INTO settings VALUES ('locale', 'de');
        PRAGMA user_version = 1;
      ''');

    final migrated = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(migrated.close);

    expect((await migrated.allPersons()).single.name, 'Anna');
    expect(await migrated.settingValue('locale'), 'de');
    await migrated.savePeer(
      Peer(nodeId: 'bob', deviceName: 'Bob', sharedKey: List.filled(32, 1)),
    );
    expect((await migrated.allPeers()).single.nodeId, 'bob');
    await migrated.upsertFamily('family', 'Familie Meier');
    expect(await migrated.familyName('family'), 'Familie Meier');
    await migrated.upsertPerson(
      Person(
        id: 'anna',
        name: 'Anna',
        dateOfBirth: DateTime.utc(2026, 1, 15),
        optionalRules: const {'influenza-under-60'},
      ),
    );
    expect((await migrated.allPersons()).single.optionalRules, {
      'influenza-under-60',
    });
    expect(
      (await migrated.customSelect('PRAGMA user_version').getSingle()).data,
      {'user_version': 4},
    );
  });
}
