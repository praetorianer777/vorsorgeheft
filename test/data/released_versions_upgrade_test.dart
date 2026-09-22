import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, QueryExecutor;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/own_appointment.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/notifications/reminder_preferences.dart';
import 'package:vorsorgeheft/sync/bundle.dart';
import 'package:vorsorgeheft/sync/hlc.dart';
import 'package:vorsorgeheft/sync/overwrite_notice.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';

import '../support/catalogs.dart';
import 'generated/schema.dart';
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;

/// One test per released version: a database written the way that version
/// left it, with every table and setting the version could fill, upgraded
/// to whatever the current schema is, and then used the way the current app
/// uses it. The current version is read from the database class, so this
/// keeps testing "every release so far to the latest" as versions move on.
///
/// What each version could write is taken from its tag, not remembered:
/// the schema number from lib/data/database.dart and the settings from the
/// files that existed at the time.
void main() {
  late SchemaVerifier verifier;
  late int current;

  setUpAll(() async {
    verifier = SchemaVerifier(GeneratedHelper());
    final fresh = openInMemoryDatabase();
    current = fresh.schemaVersion;
    await fresh.close();
  });

  for (final release in releases) {
    test('${release.name} upgrades to the current version', () async {
      final schema = await verifier.schemaAt(release.schema);
      final old = release.openOld(schema.newConnection());
      await old.customStatement(release.sql);
      await old.close();

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, current);

      await checkData(db, release);
      await checkSettings(db, release);
      await checkTimeline(db, release);
      await checkSync(db, release);
      await checkNewFeaturesOnOldData(db);
    });
  }

  test('every released version has a fixture here', () {
    // A tag without a row above is an upgrade path nobody tests. The tag
    // list is git's, so cutting a release without extending this file fails
    // the next test run. A fixture may come before its tag: that is how the
    // commit release.sh makes stays green.
    final tags = Process.runSync('git', [
      'tag',
      '--list',
      'v*',
    ]).stdout.toString().split('\n').where((t) => t.isNotEmpty).toSet();
    expect(
      releases.map((r) => r.name).toSet(),
      containsAll(tags),
      reason: 'add a Release row for every tag',
    );
  });
}

/// The features a release could have left traces of in the database.
enum Trace {
  reminderPreferences,
  syncNotices,
  catalogsSeen,
  optionalRules,
  familyName,
  ownAppointments,
  pets,
}

class Release {
  const Release(this.name, this.schema, this.traces);

  final String name;
  final int schema;
  final Set<Trace> traces;

  bool has(Trace trace) => traces.contains(trace);

  GeneratedDatabase openOld(QueryExecutor executor) => switch (schema) {
    2 => v2.DatabaseAtV2(executor),
    3 => v3.DatabaseAtV3(executor),
    4 => v4.DatabaseAtV4(executor),
    5 => v5.DatabaseAtV5(executor),
    6 => v6.DatabaseAtV6(executor),
    _ => throw StateError('no generated database for schema $schema'),
  };

  /// The rows exactly as the release wrote them: dates as ISO-8601 text,
  /// keys as base64, optional rules comma-joined, settings as JSON.
  String get sql {
    final optional = has(Trace.optionalRules)
        ? ", 'influenza-under-60,tbe'"
        : '';
    final optionalNull = has(Trace.optionalRules) ? ', NULL' : '';
    final species = schema >= 6 ? ", 'human'" : '';
    final buffer = StringBuffer('''
      INSERT INTO persons VALUES
        ('infant', 'Mila', '2026-09-01T00:00:00.000Z', 2, NULL$optionalNull$species),
        ('mother', 'Sara', '1988-06-30T00:00:00.000Z', 1, 'allergic to penicillin'$optional$species);
      INSERT INTO completions VALUES
        ('infant', 'u2', '', '2026-09-05T00:00:00.000Z', 0, 'Dr. Weber'),
        ('mother', 'td-booster', '', '2026-03-15T00:00:00.000Z', 0, NULL),
        ('infant', 'six-in-one', 'g1', '2026-11-02T00:00:00.000Z', 1, NULL);
      INSERT INTO settings VALUES
        ('locale', 'de'),
        ('node-id', 'phone-2026'),
        ('sync.private-key', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        ('sync.device-name', 'Pixel 8 (Steve)'),
        ('support.prompt.dismissed', 'true'),
        ('ics.export.records', '{"mother-td-booster":{"fingerprint":"abc","sequence":2}}');
      INSERT INTO changes VALUES
        ('person', 'infant', 'name', '1758000000000-0000-phone-2026', '"Mila"'),
        ('person', 'infant', 'dateOfBirth', '1758000000000-0001-phone-2026', '"2026-09-01T00:00:00.000Z"'),
        ('person', 'mother', 'name', '1758000000000-0002-phone-2026', '"Sara"'),
        ('person', 'mother', 'dateOfBirth', '1758000000000-0003-phone-2026', '"1988-06-30T00:00:00.000Z"'),
        ('person', 'mother', 'sex', '1758000000000-0004-phone-2026', '"female"'),
        ('person', 'mother', 'notes', '1758000000000-0005-phone-2026', '"allergic to penicillin"'),
        ('completion', 'infant|u2|', 'personId', '1758000001000-0000-phone-2026', '"infant"'),
        ('completion', 'infant|u2|', 'ruleId', '1758000001000-0001-phone-2026', '"u2"'),
        ('completion', 'infant|u2|', 'completedOn', '1758000001000-0002-phone-2026', '"2026-09-05T00:00:00.000Z"'),
        ('completion', 'infant|u2|', 'note', '1758000001000-0003-phone-2026', '"Dr. Weber"'),
        ('completion', 'mother|td-booster|', 'personId', '1758000002000-0000-phone-2026', '"mother"'),
        ('completion', 'mother|td-booster|', 'ruleId', '1758000002000-0001-phone-2026', '"td-booster"'),
        ('completion', 'mother|td-booster|', 'completedOn', '1758000002000-0002-phone-2026', '"2026-03-15T00:00:00.000Z"');
      INSERT INTO peers VALUES
        ('other-phone', 'iPhone 15 (Anna)', 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          '1758000002000-0002-phone-2026', '2026-09-21T10:00:00.000Z');
    ''');
    if (has(Trace.reminderPreferences)) {
      buffer.writeln('''
      INSERT INTO settings VALUES ('reminders.preferences',
        '{"enabled":true,"hour":8,"minute":30,"beforeWindowOpens":[14,3],"beforeDeadline":[7]}');
      ''');
    }
    if (has(Trace.syncNotices)) {
      buffer.writeln('''
      INSERT INTO settings VALUES ('sync.notices',
        '[{"personId":"infant","ruleId":"u2","doseId":null,"previousDate":"2026-09-04T00:00:00.000Z","previousSkipped":false,"currentDate":"2026-09-05T00:00:00.000Z","currentSkipped":false,"fromNodeId":"other-phone"}]');
      ''');
    }
    if (has(Trace.catalogsSeen)) {
      buffer.writeln('''
      INSERT INTO settings VALUES ('catalogs.seen',
        '{"children":"2026.09","vaccinations":"2026.09","dental":"2026.09","adults":"2026.09"}');
      ''');
    }
    if (has(Trace.familyName)) {
      buffer.writeln('''
      INSERT INTO families VALUES ('family', 'Familie Weber');
      INSERT INTO changes VALUES
        ('family', 'family', 'name', '1758000003000-0000-phone-2026', '"Familie Weber"');
      ''');
    }
    if (has(Trace.optionalRules)) {
      buffer.writeln('''
      INSERT INTO changes VALUES
        ('person', 'mother', 'optionalRules', '1758000004000-0000-phone-2026', '"influenza-under-60,tbe"');
      ''');
    }
    if (has(Trace.pets)) {
      buffer.writeln('''
      INSERT INTO persons VALUES
        ('bello', 'Bello', '2025-03-01T00:00:00.000Z', 0, NULL, 'dog-deworming', 'dog');
      INSERT INTO completions VALUES
        ('bello', 'dog-rabies', 'g1', '2025-05-24T00:00:00.000Z', 0, NULL);
      INSERT INTO changes VALUES
        ('person', 'bello', 'name', '1758000006000-0000-phone-2026', '"Bello"'),
        ('person', 'bello', 'dateOfBirth', '1758000006000-0001-phone-2026', '"2025-03-01T00:00:00.000Z"'),
        ('person', 'bello', 'species', '1758000006000-0002-phone-2026', '"dog"');
      ''');
    }
    if (has(Trace.ownAppointments)) {
      buffer.writeln('''
      INSERT INTO own_appointments VALUES
        ('eyes', 'mother', 'Augenarzt', '2026-11-03T00:00:00.000Z', 12, 'Brille mitnehmen');
      INSERT INTO changes VALUES
        ('ownAppointment', 'eyes', 'personId', '1758000005000-0000-phone-2026', '"mother"'),
        ('ownAppointment', 'eyes', 'title', '1758000005000-0001-phone-2026', '"Augenarzt"'),
        ('ownAppointment', 'eyes', 'firstOn', '1758000005000-0002-phone-2026', '"2026-11-03T00:00:00.000Z"'),
        ('ownAppointment', 'eyes', 'everyMonths', '1758000005000-0003-phone-2026', '12'),
        ('ownAppointment', 'eyes', 'note', '1758000005000-0004-phone-2026', '"Brille mitnehmen"');
      ''');
    }
    return buffer.toString();
  }

  /// The newest timestamp the fixture wrote, which the store must pick up.
  Hlc get latestHlc => Hlc.parse(
    has(Trace.pets)
        ? '1758000006000-0002-phone-2026'
        : has(Trace.ownAppointments)
        ? '1758000005000-0004-phone-2026'
        : has(Trace.optionalRules)
        ? '1758000004000-0000-phone-2026'
        : has(Trace.familyName)
        ? '1758000003000-0000-phone-2026'
        : '1758000002000-0002-phone-2026',
  );
}

const _v020 = {Trace.reminderPreferences, Trace.syncNotices, Trace.familyName};
const _v030 = {..._v020, Trace.catalogsSeen, Trace.optionalRules};
const _v050 = {..._v030, Trace.ownAppointments};
const _v060 = {..._v050, Trace.pets};

const releases = [
  Release('v0.1.0', 2, {}),
  Release('v0.2.0', 3, _v020),
  Release('v0.2.1', 3, _v020),
  Release('v0.3.0', 4, _v030),
  Release('v0.4.0', 4, _v030),
  Release('v0.5.0', 5, _v050),
  Release('v0.5.1', 5, _v050),
  Release('v0.6.0', 6, _v060),
  Release('v0.6.1', 6, _v060),
];

Future<void> checkData(AppDatabase db, Release release) async {
  final everyone = await db.allPersons();
  final people = everyone.where((p) => p.id != 'bello').toList();
  expect(people.map((p) => p.name), ['Sara', 'Mila']);
  final bello = everyone.where((p) => p.id == 'bello').firstOrNull;
  if (release.has(Trace.pets)) {
    expect(bello!.species, Species.dog);
    expect(bello.optionalRules, {'dog-deworming'});
  } else {
    expect(bello, isNull);
  }
  final sara = people.first;
  expect(sara.dateOfBirth, DateTime.utc(1988, 6, 30));
  expect(sara.sex, Sex.female);
  expect(sara.notes, 'allergic to penicillin');
  expect(
    sara.optionalRules,
    release.has(Trace.optionalRules) ? {'influenza-under-60', 'tbe'} : isEmpty,
  );
  expect(people.last.sex, Sex.notStated);
  // Every member a release before pets wrote is a person.
  expect(people.map((p) => p.species).toSet(), {Species.human});

  final completions = await db.allCompletions();
  expect(completions, hasLength(release.has(Trace.pets) ? 4 : 3));
  expect(completions.singleWhere((c) => c.ruleId == 'u2').note, 'Dr. Weber');
  final dose = completions.singleWhere((c) => c.ruleId == 'six-in-one');
  expect(dose.doseId, 'g1');
  expect(dose.skipped, isTrue);

  final peer = (await db.allPeers()).single;
  expect(peer.deviceName, 'iPhone 15 (Anna)');
  expect(peer.sharedKey, List<int>.filled(32, 1));
  expect(peer.lastSyncAt, DateTime.utc(2026, 9, 21, 10));

  expect(
    await db.familyName('family'),
    release.has(Trace.familyName) ? 'Familie Weber' : isNull,
  );
  final own = await db.allOwnAppointments();
  if (release.has(Trace.ownAppointments)) {
    expect(own.single.title, 'Augenarzt');
    expect(own.single.everyMonths, 12);
    expect(own.single.firstOn, DateTime.utc(2026, 11, 3));
  } else {
    expect(own, isEmpty);
  }
}

Future<void> checkSettings(AppDatabase db, Release release) async {
  expect(await db.settingValue('locale'), 'de');
  expect(await db.settingValue('support.prompt.dismissed'), 'true');
  expect(await db.deviceName(), 'Pixel 8 (Steve)');
  expect(await db.privateKey(), List<int>.filled(32, 0));

  final records =
      jsonDecode((await db.settingValue('ics.export.records'))!) as Map;
  expect((records['mother-td-booster'] as Map)['sequence'], 2);

  final prefs = ReminderPreferences.decode(
    await db.settingValue(ReminderPreferences.settingKey),
  );
  if (release.has(Trace.reminderPreferences)) {
    expect(prefs.hour, 8);
    expect(prefs.minute, 30);
    expect(prefs.beforeWindowOpens, [14, 3]);
    expect(prefs.beforeDeadline, [7]);
  } else {
    expect(prefs, const ReminderPreferences());
  }

  final notices = OverwriteNotice.decodeList(
    await db.settingValue(ReplicatedStore.noticesSettingKey),
  );
  if (release.has(Trace.syncNotices)) {
    expect(notices.single.fromNodeId, 'other-phone');
    expect(notices.single.previousDate, DateTime.utc(2026, 9, 4));
  } else {
    expect(notices, isEmpty);
  }

  final seen = await db.settingValue('catalogs.seen');
  if (release.has(Trace.catalogsSeen)) {
    expect((jsonDecode(seen!) as Map)['children'], '2026.09');
  } else {
    expect(seen, isNull);
  }
}

/// The upgraded data still turns into the right timeline: what was recorded
/// shows as done, the switches still switch, and the own appointment is on
/// the list.
Future<void> checkTimeline(AppDatabase db, Release release) async {
  final catalogs = shippedCatalogs();
  final completions = await db.allCompletions();
  final own = await db.allOwnAppointments();
  final today = DateTime.utc(2026, 9, 22);

  Future<List<Occurrence>> timeline(String id) async => computeOccurrences(
    person: (await db.personById(id))!,
    catalogs: catalogs,
    completions: completions,
    ownAppointments: own,
    today: today,
  );

  final mila = await timeline('infant');
  expect(
    mila.singleWhere((o) => o.rule.id == 'u2').status,
    OccurrenceStatus.done,
  );
  expect(
    mila
        .singleWhere((o) => o.rule.id == 'six-in-one' && o.doseId == 'g1')
        .status,
    OccurrenceStatus.skipped,
  );

  if (release.has(Trace.pets)) {
    final bello = await timeline('bello');
    expect(bello.map((o) => o.rule.catalogId).toSet(), {'dogs'});
    expect(
      bello.any((o) => o.rule.id == 'dog-rabies' && o.completedOn != null),
      isTrue,
    );
    expect(bello.any((o) => o.rule.id == 'dog-deworming-routine'), isTrue);
  }

  final sara = await timeline('mother');
  expect(
    sara.where((o) => o.rule.id == 'td-booster' && o.completedOn != null),
    hasLength(1),
  );
  expect(
    sara.any((o) => o.rule.id == 'influenza-under-60'),
    release.has(Trace.optionalRules),
  );
  expect(
    sara.any((o) => o.rule.id == 'own:eyes'),
    release.has(Trace.ownAppointments),
  );
}

/// The change log the release left behind still replays onto a fresh phone,
/// the store continues the old clock, and a bundle written by the first
/// release still imports.
Future<void> checkSync(AppDatabase db, Release release) async {
  final store = await ReplicatedStore.open(db);
  expect(store.nodeId, 'phone-2026');
  expect(await store.latest, release.latestHlc);

  final other = openInMemoryDatabase();
  addTearDown(other.close);
  final replica = await ReplicatedStore.open(other, nodeId: 'new-phone');
  await replica.merge(
    await store.changesSince(Hlc.zero('')),
    from: 'phone-2026',
  );
  expect(
    (await other.allPersons()).map((p) => p.name).where((n) => n != 'Bello'),
    ['Sara', 'Mila'],
  );
  if (release.has(Trace.pets)) {
    expect((await other.personById('bello'))!.species, Species.dog);
  }
  expect(
    (await other.allCompletions()).map((c) => c.ruleId).toSet(),
    containsAll(['u2', 'td-booster']),
  );
  expect(
    await other.familyName('family'),
    release.has(Trace.familyName) ? 'Familie Weber' : isNull,
  );
  expect(
    (await other.allOwnAppointments()).map((a) => a.title),
    release.has(Trace.ownAppointments) ? ['Augenarzt'] : isEmpty,
  );

  final golden = File('test/sync/golden/family-v1.vorsorge').readAsBytesSync();
  final contents = await SyncBundle.open(golden, 'correct horse');
  await store.merge(contents.changes, from: contents.nodeId);
  expect(
    (await db.allPersons()).map((p) => p.name).where((n) => n != 'Bello'),
    ['Sara', 'Mila'],
  );
}

/// What was added after the release works on top of its data, and the
/// foreign keys the upgrade must not lose still cascade.
Future<void> checkNewFeaturesOnOldData(AppDatabase db) async {
  final store = await ReplicatedStore.open(db);
  await store.saveOwnAppointment(
    OwnAppointment(
      id: 'physio',
      personId: 'infant',
      title: 'Physio',
      firstOn: DateTime.utc(2026, 10, 1),
      everyMonths: 3,
    ),
  );
  expect(
    (await db.allOwnAppointments()).map((a) => a.title),
    contains('Physio'),
  );
  await store.recordCompletion(
    Completion(
      personId: 'infant',
      ruleId: 'own:physio',
      completedOn: DateTime.utc(2026, 10, 2),
    ),
  );
  expect(
    (await db.allCompletions()).map((c) => c.ruleId),
    contains('own:physio'),
  );

  await store.deletePerson('infant');
  expect(
    (await db.allPersons()).map((p) => p.name).where((n) => n != 'Bello'),
    ['Sara'],
  );
  expect(
    (await db.allCompletions()).map((c) => c.personId).toSet(),
    isNot(contains('infant')),
  );
  expect(
    (await db.allOwnAppointments()).map((a) => a.personId).toSet(),
    isNot(contains('infant')),
  );
}
