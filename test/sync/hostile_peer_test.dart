import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/sync/hlc.dart';
import 'package:vorsorgeheft/sync/sync_protocol.dart';
import 'package:vorsorgeheft/sync/sync_transport.dart';

import '../support/sync_devices.dart';

/// What the app does when the thing on the other end of the connection is not
/// another copy of it.
///
/// The sync listens on the local network, so anything else on that network
/// can open a connection and say whatever it likes. None of it may crash the
/// app, leave it hanging, or write a single change into the database.
void main() {
  late LoopbackNetwork network;
  late Device alice;
  late Device bob;

  final anna = Person(
    id: 'anna',
    name: 'Anna',
    dateOfBirth: DateTime.utc(2026, 1, 15),
  );

  setUp(() async {
    network = LoopbackNetwork();
    alice = await Device.open('alice', network);
    bob = await Device.open('bob', network);
  });
  tearDown(() async {
    await alice.close();
    await bob.close();
  });

  /// Something on the network that is not this app.
  Future<SyncChannel> knockOn(String nodeId) =>
      LoopbackTransport(network).connect(nodeId);

  Future<void> say(SyncChannel channel, String text) =>
      channel.send(Uint8List.fromList(utf8.encode(text)));

  group('a caller that does not speak the protocol', () {
    test('is hung up on, and the phone still syncs afterwards', () async {
      for (final nonsense in [
        'not json at all',
        '[1, 2, 3]',
        '"a bare string"',
        '{"type": "hello from somewhere else"}',
      ]) {
        final channel = await knockOn('bob');
        await say(channel, nonsense);
        expect(await channel.receive(), isNull, reason: nonsense);
        await channel.close();
      }

      await pair(bob, alice);
      await alice.store.savePerson(anna);
      final result = await alice.engine.syncWith('bob');
      expect(result.sent, 6);
      expect((await bob.db.allPersons()).single.name, 'Anna');
    });

    test('writes nothing, paired or not', () async {
      await pair(bob, alice);
      final channel = await knockOn('bob');
      await say(
        channel,
        '{"type": "changes", "changes": [{"entity": '
        '"person", "id": "ghost", "field": "name", "hlc": '
        '"1758000000000-0000-ghost", "value": "Ghost"}]}',
      );
      await channel.receive();
      await channel.close();

      expect(await bob.db.allPersons(), isEmpty);
      expect(await bob.db.changesSince(Hlc.zero('')), isEmpty);
    });
  });

  group('a phone that answers under a paired name', () {
    /// Takes the paired phone's place on the wire: the same node id, none of
    /// the protocol.
    Future<void> impersonate(
      String nodeId,
      Future<void> Function(SyncChannel channel) answer,
    ) async {
      await bob.engine.stop();
      await LoopbackTransport(network).listen(nodeId, answer);
    }

    setUp(() => pair(bob, alice));

    test('an answer that is not JSON fails the exchange', () async {
      await impersonate('bob', (channel) async {
        await channel.receive();
        await say(channel, 'certainly not JSON');
      });

      await expectLater(
        alice.engine.syncWith('bob'),
        throwsA(isA<SyncProtocolException>()),
      );
      expect(await alice.db.allPersons(), isEmpty);
    });

    test('hanging up mid-exchange fails the exchange', () async {
      await impersonate('bob', (channel) async {
        await channel.receive();
        await channel.close();
      });

      await expectLater(
        alice.engine.syncWith('bob'),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('a reply of the wrong type fails the exchange', () async {
      await impersonate('bob', (channel) async {
        await channel.receive();
        await say(channel, '{"type": "changes"}');
      });

      await expectLater(
        alice.engine.syncWith('bob'),
        throwsA(isA<SyncProtocolException>()),
      );
    });
  });
}
