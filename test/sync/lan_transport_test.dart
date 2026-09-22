import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/sync/lan_transport.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';
import 'package:vorsorgeheft/sync/sync_protocol.dart';
import 'package:vorsorgeheft/sync/sync_transport.dart';

/// The socket half of the LAN transport, over the loopback interface with
/// the address given by hand. Discovery needs a network that carries
/// multicast, which a test runner does not promise, so it is not asserted
/// on here; the manual path is what it falls back to anyway.
void main() {
  late LanTransport server;
  late LanTransport client;

  setUp(() {
    server = LanTransport(lookupTimeout: const Duration(seconds: 2));
    client = LanTransport(lookupTimeout: const Duration(seconds: 2));
  });
  tearDown(() async {
    await server.stop();
    await client.stop();
  });

  test('frames arrive whole, in order, in both directions', () async {
    final seen = <String>[];
    await server.listen('server', (channel) async {
      final frame = await channel.receive();
      seen.add(String.fromCharCodes(frame!));
      await channel.send(Uint8List.fromList('pong'.codeUnits));
      final big = await channel.receive();
      seen.add('${big!.length}');
    });

    final channel = await client.connect(
      'server',
      address: '127.0.0.1:${server.port}',
    );
    await channel.send(Uint8List.fromList('ping'.codeUnits));
    expect(String.fromCharCodes((await channel.receive())!), 'pong');
    // Well past what one TCP segment holds, so the reader has to reassemble.
    await channel.send(Uint8List(300000));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await channel.close();

    expect(seen, ['ping', '300000']);
  });

  test('a peer nobody listens for is unreachable', () async {
    await expectLater(
      client.connect('ghost', address: '127.0.0.1:1'),
      throwsA(isA<PeerUnreachableException>()),
    );
    await expectLater(
      client.connect('ghost', address: 'not-an-address'),
      throwsA(isA<PeerUnreachableException>()),
    );
  });

  test('two engines converge over a real socket', () async {
    final aliceDb = openInMemoryDatabase();
    final bobDb = openInMemoryDatabase();
    addTearDown(aliceDb.close);
    addTearDown(bobDb.close);
    final clock = DateTime.utc(2026, 9, 20);
    final aliceStore = await ReplicatedStore.open(
      aliceDb,
      nodeId: 'alice',
      clock: () => clock,
    );
    final bobStore = await ReplicatedStore.open(
      bobDb,
      nodeId: 'bob',
      clock: () => clock,
    );
    final alice = SyncEngine(
      store: aliceStore,
      registry: aliceDb,
      transport: server,
      clock: () => clock,
    );
    final bob = SyncEngine(
      store: bobStore,
      registry: bobDb,
      transport: client,
      clock: () => clock,
    );
    await alice.start();
    await bob.pairWith((await alice.pairingPayload()).encode());
    await aliceStore.savePerson(
      Person(id: 'anna', name: 'Anna', dateOfBirth: DateTime.utc(2026, 1, 15)),
    );

    final result = await bob.syncWith(
      'alice',
      address: '127.0.0.1:${server.port}',
    );

    expect(result.received, 6);
    expect((await bobDb.personById('anna'))!.name, 'Anna');
    expect(await aliceDb.peer('bob'), isNotNull);
  });
}
