import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/data/database.dart';
import 'package:vorsorgereminder/data/database_provider.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/sync/device_info.dart';
import 'package:vorsorgereminder/sync/hlc.dart';
import 'package:vorsorgereminder/sync/replicated_store.dart';
import 'package:vorsorgereminder/sync/sync_protocol.dart';
import 'package:vorsorgereminder/sync/sync_transport.dart';

/// A phone: its own database, store, engine and clock, on the shared wire.
class Device {
  Device._(this.name, this.db, this.store, this.engine, this._clock);

  static Future<Device> open(
    String name,
    LoopbackNetwork network, {
    String? model,
  }) async {
    final db = openInMemoryDatabase();
    final clock = _Clock(DateTime.utc(2026, 9, 20));
    final store = await ReplicatedStore.open(
      db,
      nodeId: name,
      clock: clock.read,
    );
    final engine = SyncEngine(
      store: store,
      registry: db,
      transport: LoopbackTransport(network),
      clock: clock.read,
      deviceInfo: FixedDeviceInfo(model),
    );
    await engine.start();
    return Device._(name, db, store, engine, clock);
  }

  final String name;
  final AppDatabase db;
  final ReplicatedStore store;
  final SyncEngine engine;
  final _Clock _clock;

  void advance(Duration by) => _clock.advance(by);

  Future<void> close() async {
    await engine.stop();
    await db.close();
  }
}

class _Clock {
  _Clock(this._now);

  DateTime _now;

  DateTime read() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

/// One phone shows its code, the other scans it.
Future<void> pair(Device shows, Device scans) async {
  final code = (await shows.engine.pairingPayload()).encode();
  await scans.engine.pairWith(code);
}

final anna = Person(
  id: 'anna',
  name: 'Anna',
  dateOfBirth: DateTime.utc(2026, 1, 15),
  sex: Sex.female,
);

final mila = Person(
  id: 'mila',
  name: 'Mila',
  dateOfBirth: DateTime.utc(2026, 9, 1),
);

void main() {
  late LoopbackNetwork network;
  late Device alice;
  late Device bob;

  setUp(() async {
    network = LoopbackNetwork();
    alice = await Device.open('alice', network);
    bob = await Device.open('bob', network);
  });
  tearDown(() async {
    await alice.close();
    await bob.close();
  });

  group('pairing', () {
    test('scanning the code stores the peer on the scanning side', () async {
      await pair(alice, bob);
      final stored = await bob.db.peer('alice');
      expect(stored!.deviceName, 'Phone');
      expect(stored.sharedKey, hasLength(32));
      expect(await alice.db.peer('bob'), isNull);
    });

    test('an unnamed phone goes by its model', () async {
      final pixel = await Device.open('pixel', network, model: 'Pixel 8');
      addTearDown(pixel.close);

      expect(await pixel.engine.deviceName(), 'Pixel 8');
      final code = (await pixel.engine.pairingPayload(
        defaultName: 'My phone',
      )).encode();
      await bob.engine.pairWith(code);
      expect((await bob.db.peer('pixel'))!.deviceName, 'Pixel 8');
      expect(await pixel.db.deviceName(), isNull);
    });

    test('a chosen name wins over the model', () async {
      final pixel = await Device.open('pixel', network, model: 'Pixel 8');
      addTearDown(pixel.close);
      await pixel.engine.rename("Mum's phone");

      final code = (await pixel.engine.pairingPayload()).encode();
      await bob.engine.pairWith(code);
      expect((await bob.db.peer('pixel'))!.deviceName, "Mum's phone");
    });

    test('without a model the localised default is kept', () async {
      final code = (await alice.engine.pairingPayload(
        defaultName: 'My phone',
      )).encode();
      await bob.engine.pairWith(code);
      expect((await bob.db.peer('alice'))!.deviceName, 'My phone');
      expect(await alice.db.deviceName(), 'My phone');
    });

    test(
      'the first exchange completes the pairing on the showing side',
      () async {
        await pair(alice, bob);
        await bob.engine.syncWith('alice');

        final onAlice = await alice.db.peer('bob');
        final onBob = await bob.db.peer('alice');
        expect(onAlice!.sharedKey, onBob!.sharedKey);
      },
    );

    test(
      'a device that connects after the code was put away is refused',
      () async {
        final code = (await alice.engine.pairingPayload()).encode();
        alice.advance(const Duration(minutes: 6));
        await bob.engine.pairWith(code);

        await expectLater(
          bob.engine.syncWith('alice'),
          throwsA(isA<UnknownPeerException>()),
        );
        expect(await alice.db.peer('bob'), isNull);
      },
    );

    test('a device that is not paired cannot sync', () async {
      await expectLater(
        bob.engine.syncWith('alice'),
        throwsA(isA<UnknownPeerException>()),
      );
    });

    test('a peer that is not listening is reported as unreachable', () async {
      await pair(alice, bob);
      await alice.engine.stop();
      await expectLater(
        bob.engine.syncWith('alice'),
        throwsA(isA<PeerUnreachableException>()),
      );
    });

    test('the private key is generated once and kept', () async {
      final first = await alice.engine.pairingPayload();
      final second = await alice.engine.pairingPayload();
      expect(second.publicKey, first.publicKey);
      expect(await alice.db.privateKey(), isNotNull);
    });

    test('scanning its own code is refused', () async {
      final code = (await alice.engine.pairingPayload()).encode();
      expect(() => alice.engine.pairWith(code), throwsFormatException);
    });
  });

  group('exchanging', () {
    setUp(() => pair(alice, bob));

    test('a change on each side reaches the other', () async {
      await alice.store.savePerson(anna);
      await bob.store.savePerson(mila);

      final result = await bob.engine.syncWith('alice');

      expect(result.received, 4);
      expect(result.sent, 4);
      expect((await alice.db.allPersons()).map((p) => p.id), ['anna', 'mila']);
      expect((await bob.db.allPersons()).map((p) => p.id), ['anna', 'mila']);
    });

    test('a second exchange with nothing new carries nothing', () async {
      await alice.store.savePerson(anna);
      await bob.store.savePerson(mila);
      await bob.engine.syncWith('alice');

      final again = await bob.engine.syncWith('alice');
      expect(again.nothingNew, isTrue);
      expect(again.received, 0);
      expect(again.sent, 0);

      final fromAlice = await alice.engine.syncWith('bob');
      expect(fromAlice.nothingNew, isTrue);
    });

    test(
      'a later change is the only thing the next exchange carries',
      () async {
        await alice.store.savePerson(anna);
        await bob.engine.syncWith('alice');

        alice.advance(const Duration(minutes: 1));
        await alice.store.recordCompletion(
          Completion(
            personId: 'anna',
            ruleId: 'u6',
            completedOn: DateTime.utc(2026, 11, 2),
          ),
        );

        final result = await bob.engine.syncWith('alice');
        expect(result.received, 6);
        expect((await bob.db.allCompletions()).single.ruleId, 'u6');
      },
    );

    test('the mark held for a peer advances with every exchange', () async {
      await alice.store.savePerson(anna);
      await bob.engine.syncWith('alice');
      final first = (await bob.db.peer('alice'))!.lastSyncHlc!;
      expect(first, (await alice.store.latest)!);

      alice.advance(const Duration(minutes: 1));
      await alice.store.deletePerson('anna');
      await bob.engine.syncWith('alice');
      final second = (await bob.db.peer('alice'))!.lastSyncHlc!;

      expect(second > first, isTrue);
      expect(
        (await bob.db.peer('alice'))!.lastSyncAt,
        DateTime.utc(2026, 9, 20),
      );
    });

    test("the responder records the initiator's mark too", () async {
      await bob.store.savePerson(anna);
      await bob.engine.syncWith('alice');
      expect((await alice.db.peer('bob'))!.lastSyncHlc, await bob.store.latest);
    });

    test('a write landing between two exchanges is not skipped', () async {
      // Alice writes after Bob has pulled from her; Bob's clock is well ahead,
      // so the changes he then sends her sort above her write. Her mark must
      // still be the one from the delta, or the write would never be sent.
      await alice.store.savePerson(anna);
      await bob.engine.syncWith('alice');

      alice.advance(const Duration(seconds: 1));
      await alice.store.savePerson(
        Person(id: 'anna', name: 'Anna B.', dateOfBirth: anna.dateOfBirth),
      );
      bob.advance(const Duration(minutes: 5));
      await bob.store.savePerson(mila);

      await bob.engine.syncWith('alice');
      expect((await bob.db.personById('anna'))!.name, 'Anna B.');
    });

    test('both sides hear about a finished exchange', () async {
      final onAlice = alice.engine.completed.first;
      await alice.store.savePerson(anna);
      final result = await bob.engine.syncWith('alice');
      expect((await onAlice).sent, result.received);
    });
  });

  group('what never travels', () {
    test('neither the peers nor the private key are in a change set', () async {
      await pair(alice, bob);
      await bob.engine.syncWith('alice');
      await alice.engine.rename('Kitchen phone');

      for (final device in [alice, bob]) {
        expect(
          await device.db.changesSince(Hlc.zero('')),
          isEmpty,
          reason: device.name,
        );
      }
    });
  });
}
