import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// What one phone shows the other as a QR code: who it is and how to agree on
/// a key with it.
///
/// The payload carries the public half of the key pair only. Anyone who reads
/// the code learns the node id and a public key, neither of which lets them
/// decrypt anything; what they cannot learn is the private key, which
/// [DeviceIdentity] never serialises into anything that leaves the device.
class PairingPayload {
  const PairingPayload({
    required this.nodeId,
    required this.publicKey,
    required this.deviceName,
  });

  /// Parses what a scanner read. Anything that is not a pairing code of this
  /// app, or one from a newer format, is a [FormatException] rather than a
  /// half-filled payload.
  factory PairingPayload.decode(String encoded) {
    if (!encoded.startsWith(_prefix)) {
      throw const FormatException('not a pairing code');
    }
    final Object? json;
    try {
      json = jsonDecode(
        utf8.decode(base64Url.decode(encoded.substring(_prefix.length))),
      );
    } on Object {
      throw const FormatException('pairing code is not readable');
    }
    if (json is! Map || json['v'] != 1) {
      throw const FormatException('unknown pairing code version');
    }
    final nodeId = json['nodeId'];
    final key = json['publicKey'];
    final name = json['deviceName'];
    if (nodeId is! String || key is! String || name is! String) {
      throw const FormatException('pairing code is incomplete');
    }
    final keyBytes = base64.decode(key);
    if (keyBytes.length != DeviceIdentity.keyLength) {
      throw const FormatException('pairing code carries no X25519 key');
    }
    return PairingPayload(
      nodeId: nodeId,
      publicKey: keyBytes,
      deviceName: name,
    );
  }

  static const _prefix = 'vorsorgereminder:pair:';

  final String nodeId;
  final List<int> publicKey;
  final String deviceName;

  /// The text the QR code carries. Base64url keeps it within the alphanumeric
  /// range a QR encodes densely, and the prefix lets a scanner tell a pairing
  /// code from any other code it happens to see.
  String encode() =>
      _prefix +
      base64Url.encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'nodeId': nodeId,
            'publicKey': base64.encode(publicKey),
            'deviceName': deviceName,
          }),
        ),
      );
}

/// This device's X25519 key pair.
///
/// The private key is generated once, kept in the Settings table and never
/// leaves the device: the pairing code carries [publicKey] only, and
/// [sharedKeyWith] uses the private half locally to agree on a key with a
/// peer. It is stored unencrypted, which is as safe as the rest of the
/// database on the same phone.
class DeviceIdentity {
  DeviceIdentity._(this._privateKey, this.publicKey);

  /// Restores a key pair from the private key bytes the database holds.
  static Future<DeviceIdentity> fromPrivateKey(List<int> privateKey) async {
    final pair = await _x25519.newKeyPairFromSeed(privateKey);
    final public = await pair.extractPublicKey();
    return DeviceIdentity._(Uint8List.fromList(privateKey), public.bytes);
  }

  static Future<DeviceIdentity> generate() async {
    final pair = await _x25519.newKeyPair();
    return fromPrivateKey(await pair.extractPrivateKeyBytes());
  }

  static const keyLength = 32;
  static final _x25519 = X25519();

  final Uint8List _privateKey;
  final List<int> publicKey;

  /// The private half, for storing it. Nothing else should read this.
  List<int> get privateKey => _privateKey;

  /// The symmetric key both sides of a pairing end up with.
  ///
  /// The ECDH result goes through HKDF rather than being used directly: the
  /// raw X25519 output is not uniformly distributed, and the info string binds
  /// the key to this pairing so the same two phones re-paired for a different
  /// purpose would never share it.
  Future<List<int>> sharedKeyWith({
    required String ownNodeId,
    required String peerNodeId,
    required List<int> peerPublicKey,
  }) async {
    final pair = await _x25519.newKeyPairFromSeed(_privateKey);
    final secret = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
    );
    final nodes = [ownNodeId, peerNodeId]..sort();
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: keyLength)
        .deriveKey(
          secretKey: secret,
          info: utf8.encode('vorsorgereminder sync v1 ${nodes.join(' ')}'),
        );
    return derived.extractBytes();
  }
}
