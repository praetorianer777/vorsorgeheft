import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/schedule_engine.dart';
import 'package:vorsorgeheft/sync/bundle.dart';
import 'package:vorsorgeheft/sync/hlc.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';

import '../support/catalogs.dart';

/// A bundle as a phone of 2026 wrote it, opened by the phone that replaces it.
///
/// The file in the repo is the promise: whatever the format becomes, a file
/// written today still opens, on either platform, because the bytes carry no
/// platform in them. A test that regenerated the file on every run would
/// promise nothing, so it is rewritten only on request:
///
///     UPDATE_BUNDLE_GOLDEN=1 flutter test test/sync/bundle_golden_test.dart
///
/// When the format version changes, add a new file next to the old one and
/// keep the old one tested.
const goldenPath = 'test/sync/golden/family-v1.vorsorge';
const password = 'correct horse';

final sara = Person(
  id: 'mother',
  name: 'Sara',
  dateOfBirth: DateTime.utc(1988, 6, 30),
  sex: Sex.female,
);
final mila = Person(
  id: 'infant',
  name: 'Mila',
  dateOfBirth: DateTime.utc(2026, 9, 1),
);
final tetanus = Completion(
  personId: 'mother',
  ruleId: 'td-booster',
  completedOn: DateTime.utc(2026, 3, 15),
);
final u2 = Completion(
  personId: 'infant',
  ruleId: 'u2',
  completedOn: DateTime.utc(2026, 9, 5),
  note: 'Dr. Weber',
);

Future<List<int>> writtenIn2026() async {
  final db = openInMemoryDatabase();
  final store = await ReplicatedStore.open(
    db,
    nodeId: 'android-2026',
    clock: () => DateTime.utc(2026, 9, 20, 10),
  );
  await store.savePerson(sara);
  await store.savePerson(mila);
  await store.recordCompletion(tetanus);
  await store.recordCompletion(u2);
  final bytes = await SyncBundle.seal(
    nodeId: store.nodeId,
    changes: await store.changesSince(Hlc.zero('')),
    password: password,
  );
  await db.close();
  return bytes;
}

void main() {
  final golden = File(goldenPath);

  setUpAll(() async {
    if (Platform.environment['UPDATE_BUNDLE_GOLDEN'] == '1') {
      golden
        ..createSync(recursive: true)
        ..writeAsBytesSync(await writtenIn2026());
    }
  });

  test('the file from 2026 opens on the phone of 2036', () async {
    final contents = await SyncBundle.open(golden.readAsBytesSync(), password);
    expect(contents.nodeId, 'android-2026');

    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final store = await ReplicatedStore.open(
      db,
      nodeId: 'iphone-2036',
      clock: () => DateTime.utc(2036, 10, 1, 9),
    );
    final result = await store.merge(contents.changes, from: contents.nodeId);
    expect(result.overwritten, isEmpty);

    final people = await db.allPersons();
    expect(people.map((p) => p.name), ['Sara', 'Mila']);
    expect(people.first.dateOfBirth, sara.dateOfBirth);
    expect(people.first.sex, Sex.female);

    final completions = await db.allCompletions();
    expect(completions, hasLength(2));
    final booster = completions.singleWhere((c) => c.ruleId == 'td-booster');
    expect(booster.completedOn, tetanus.completedOn);
    final earlyCheckUp = completions.singleWhere((c) => c.ruleId == 'u2');
    expect(earlyCheckUp.note, 'Dr. Weber');
  });

  test('ten years on, the booster is due from the recorded date', () async {
    final contents = await SyncBundle.open(golden.readAsBytesSync(), password);
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final store = await ReplicatedStore.open(db, nodeId: 'iphone-2036');
    await store.merge(contents.changes);

    final occurrences = computeOccurrences(
      person: (await db.personById('mother'))!,
      catalogs: shippedCatalogs(),
      completions: await db.allCompletions(),
      today: DateTime.utc(2036, 10, 1),
    );
    final booster = occurrences.singleWhere(
      (o) => o.rule.id == 'td-booster' && o.status != OccurrenceStatus.done,
    );
    expect(booster.windowStart, DateTime.utc(2036, 3, 15));
    expect(booster.status, OccurrenceStatus.due);
  });

  test('the bytes name no platform', () {
    // What is not in the file cannot stop it opening elsewhere: no path, no
    // platform, no locale. Only the magic is in the clear, so the check is
    // that the header is what the reader expects and nothing else is
    // readable.
    final bytes = golden.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(4)), 'VSRB');
    expect(bytes[4], 1);
    expect(String.fromCharCodes(bytes), isNot(contains('android')));
    expect(String.fromCharCodes(bytes), isNot(contains('Sara')));
  });
}
