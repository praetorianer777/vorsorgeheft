import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when a message was not produced under the expected key, or was
/// changed in transit. Never turned into plaintext: AES-GCM authenticates
/// before it decrypts, so a forged frame is an error, not garbage.
class TamperedMessageException implements Exception {
  const TamperedMessageException();

  @override
  String toString() => 'TamperedMessageException';
}

/// AES-256-GCM under one shared key, with a fresh random nonce per message.
///
/// A message on the wire is `nonce || ciphertext || tag`. The nonce is random
/// rather than a counter because both sides send under the same key and
/// neither knows how many messages the other has already sent; 96 random bits
/// per message make a repeat vanishingly unlikely over the lifetime of a
/// pairing.
class SessionCipher {
  SessionCipher(List<int> key)
    : assert(key.length == 32, 'AES-256 needs a 32-byte key'),
      _key = SecretKey(key);

  static final _aes = AesGcm.with256bits();
  static const _nonceLength = AesGcm.defaultNonceLength;
  static const _macLength = 16;

  final SecretKey _key;

  Future<Uint8List> seal(List<int> plaintext) async {
    final box = await _aes.encrypt(plaintext, secretKey: _key);
    return box.concatenation();
  }

  Future<Uint8List> open(List<int> sealed) async {
    if (sealed.length < _nonceLength + _macLength) {
      throw const TamperedMessageException();
    }
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    try {
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: _key));
    } on SecretBoxAuthenticationError {
      throw const TamperedMessageException();
    }
  }
}
