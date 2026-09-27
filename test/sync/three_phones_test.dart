import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/sync/sync_transport.dart';

import '../support/sync_devices.dart';

/// Two parents and a grandmother, or one parent, one phone at work and one
/// tablet at home: more than two phones is an ordinary family, and the phone
/// in the middle has to carry what it heard to the one on the other side.
///
/// Until this worked, an exchange sent only the changes that device had made
/// itself, so a family with three phones needed every pair to meet. Anything
/// that arrived as a file was never passed on either.
void main() {
  late LoopbackNetwork network;
  late Device mum;
  late Device dad;
  late Device granny;

  final mila = Person(
    id: 'mila',
    name: 'Mila',
    dateOfBirth: DateTime.utc(2026, 9, 1),
  );

  setUp(() async {
    network = LoopbackNetwork();
    mum = await Device.open('mum', network);
    dad = await Device.open('dad', network);
    granny = await Device.open('granny', network);
  });
  tearDown(() async {
    await mum.close();
    await dad.close();
    await granny.close();
  });

  test('a change reaches the third phone through the middle one', () async {
    await pair(mum, dad);
    await pair(dad, granny);

    await mum.store.savePerson(mila);
    await dad.engine.syncWith('mum');
    expect((await dad.db.allPersons()).single.name, 'Mila');

    final result = await granny.engine.syncWith('dad');

    expect(result.received, 7, reason: 'the seven fields of a person');
    expect((await granny.db.allPersons()).single.name, 'Mila');
  });

  test('what the middle phone learned later still travels', () async {
    await pair(mum, dad);
    await dad.engine.syncWith('mum');
    await pair(dad, granny);
    await granny.engine.syncWith('dad');

    // The order a timestamp watermark cannot survive: the far phone moves
    // its mark past the moment the near one wrote, and only then does the
    // middle phone hear about that write.
    await mum.store.savePerson(mila);
    dad.advance(const Duration(minutes: 5));
    granny.advance(const Duration(minutes: 5));
    await granny.engine.syncWith('dad');
    expect(await granny.db.allPersons(), isEmpty);

    await dad.engine.syncWith('mum');
    await granny.engine.syncWith('dad');

    expect((await granny.db.allPersons()).single.name, 'Mila');
  });

  test('all three end up with the same family', () async {
    await pair(mum, dad);
    await dad.engine.syncWith('mum');
    await pair(dad, granny);
    await granny.engine.syncWith('dad');

    await mum.store.savePerson(mila);
    await dad.store.savePerson(
      Person(id: 'tom', name: 'Tom', dateOfBirth: DateTime.utc(2019, 4, 2)),
    );
    await granny.store.savePerson(
      Person(id: 'oma', name: 'Oma', dateOfBirth: DateTime.utc(1951, 7, 9)),
    );

    // Each phone meets the middle one, twice round.
    for (var i = 0; i < 2; i++) {
      await dad.engine.syncWith('mum');
      await granny.engine.syncWith('dad');
    }
    await dad.engine.syncWith('mum');

    for (final device in [mum, dad, granny]) {
      expect((await device.db.allPersons()).map((p) => p.id).toSet(), {
        'mila',
        'tom',
        'oma',
      }, reason: device.name);
    }
  });

  test('a recorded appointment travels the same way', () async {
    await pair(mum, dad);
    await pair(dad, granny);
    await mum.store.savePerson(mila);
    await mum.store.recordCompletion(
      Completion(
        personId: 'mila',
        ruleId: 'u3',
        completedOn: DateTime.utc(2026, 9, 25),
      ),
    );

    await dad.engine.syncWith('mum');
    await granny.engine.syncWith('dad');

    final onGranny = (await granny.db.allCompletions()).single;
    expect(onGranny.ruleId, 'u3');
    expect(onGranny.completedOn, DateTime.utc(2026, 9, 25));
  });

  test('a second exchange carries nothing the peer already has', () async {
    await pair(mum, dad);
    await pair(dad, granny);
    await mum.store.savePerson(mila);
    await dad.engine.syncWith('mum');
    await granny.engine.syncWith('dad');

    final again = await granny.engine.syncWith('dad');
    expect(again.received, 0);
    expect(again.sent, 0);
    expect(again.nothingNew, isTrue);
  });

  test('nobody is sent their own changes back', () async {
    await pair(mum, dad);
    await mum.store.savePerson(mila);
    await dad.engine.syncWith('mum');

    // Dad now holds Mila's six fields, all of them stamped by mum. Mum asks
    // dad for what is new, and there is nothing in it for her.
    final back = await mum.engine.syncWith('dad');
    expect(back.received, 0);
  });
}
