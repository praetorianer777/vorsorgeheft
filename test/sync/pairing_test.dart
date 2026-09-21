import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/sync/pairing.dart';

void main() {
  test('the pairing code round-trips', () async {
    final identity = await DeviceIdentity.generate();
    final payload = PairingPayload(
      nodeId: 'alice',
      publicKey: identity.publicKey,
      deviceName: "Alice's phone",
    );

    final decoded = PairingPayload.decode(payload.encode());
    expect(decoded.nodeId, 'alice');
    expect(decoded.publicKey, identity.publicKey);
    expect(decoded.deviceName, "Alice's phone");
  });

  test(
    'the code carries the public key and nothing of the private one',
    () async {
      final identity = await DeviceIdentity.generate();
      final encoded = PairingPayload(
        nodeId: 'alice',
        publicKey: identity.publicKey,
        deviceName: 'Phone',
      ).encode();

      expect(PairingPayload.decode(encoded).publicKey, identity.publicKey);
      expect(identity.privateKey, isNot(identity.publicKey));
      expect(encoded, isNot(contains(identity.privateKey.join(','))));
    },
  );

  test('anything that is not a pairing code is rejected', () {
    for (final junk in [
      '',
      'https://example.com',
      'vorsorgereminder:pair:!!',
    ]) {
      expect(() => PairingPayload.decode(junk), throwsFormatException);
    }
  });

  test('two independently generated key pairs derive the same key', () async {
    final alice = await DeviceIdentity.generate();
    final bob = await DeviceIdentity.generate();

    final fromAlice = await alice.sharedKeyWith(
      ownNodeId: 'alice',
      peerNodeId: 'bob',
      peerPublicKey: bob.publicKey,
    );
    final fromBob = await bob.sharedKeyWith(
      ownNodeId: 'bob',
      peerNodeId: 'alice',
      peerPublicKey: alice.publicKey,
    );

    expect(fromAlice, fromBob);
    expect(fromAlice, hasLength(32));
  });

  test('a third key pair does not arrive at the same key', () async {
    final alice = await DeviceIdentity.generate();
    final bob = await DeviceIdentity.generate();
    final eve = await DeviceIdentity.generate();

    final honest = await alice.sharedKeyWith(
      ownNodeId: 'alice',
      peerNodeId: 'bob',
      peerPublicKey: bob.publicKey,
    );
    final impostor = await eve.sharedKeyWith(
      ownNodeId: 'alice',
      peerNodeId: 'bob',
      peerPublicKey: bob.publicKey,
    );
    expect(impostor, isNot(honest));
  });

  test(
    'a key pair restored from its private key is the same identity',
    () async {
      final original = await DeviceIdentity.generate();
      final restored = await DeviceIdentity.fromPrivateKey(original.privateKey);
      expect(restored.publicKey, original.publicKey);
    },
  );
}
