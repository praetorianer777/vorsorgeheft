import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'change.dart';
import 'hlc.dart';
import 'session_cipher.dart';

/// The password did not unlock the bundle.
///
/// Indistinguishable from a bundle that was altered after it was written:
/// AES-GCM only reports that the tag does not match, and telling the two apart
/// would mean decrypting first and checking later.
class WrongPasswordException implements Exception {
  const WrongPasswordException();

  @override
  String toString() => 'WrongPasswordException';
}

/// The file is not a bundle this app wrote.
class BundleFormatException implements Exception {
  const BundleFormatException(this.message);

  final String message;

  @override
  String toString() => 'BundleFormatException: $message';
}

class BundleContents {
  const BundleContents({required this.nodeId, required this.changes});

  /// The device that wrote the bundle.
  final String nodeId;
  final List<Change> changes;
}

/// The same change set the LAN exchange carries, as a file for when the two
/// phones do not share a network.
///
/// Layout: magic, format version, PBKDF2 iteration count, a random salt, then
/// the sealed payload exactly as [SessionCipher] writes it. The key comes
/// from the password through PBKDF2-HMAC-SHA256; the iteration count is part
/// of the file so a later version can raise it without breaking bundles that
/// were written before.
class SyncBundle {
  const SyncBundle._();

  static const fileExtension = 'vorsorge';
  static const defaultIterations = 100000;

  static const _magic = [0x56, 0x53, 0x52, 0x42];
  static const _version = 1;
  static const _saltLength = 16;
  static const _headerLength = 4 + 1 + 4 + _saltLength;

  static Future<Uint8List> seal({
    required String nodeId,
    required Iterable<Change> changes,
    required String password,
    int iterations = defaultIterations,
  }) async {
    final salt = SecretKeyData.random(length: _saltLength).bytes;
    final cipher = SessionCipher(await _key(password, salt, iterations));
    final plaintext = utf8.encode(
      jsonEncode({
        'v': _version,
        'nodeId': nodeId,
        'changes': [for (final c in changes) c.toJson()],
      }),
    );
    final out = BytesBuilder()
      ..add(_magic)
      ..addByte(_version)
      ..add((ByteData(4)..setUint32(0, iterations)).buffer.asUint8List())
      ..add(salt)
      ..add(await cipher.seal(plaintext));
    return out.toBytes();
  }

  static Future<BundleContents> open(List<int> bytes, String password) async {
    if (bytes.length < _headerLength ||
        !_startsWith(bytes, _magic) ||
        bytes[4] != _version) {
      throw const BundleFormatException('not a sync bundle');
    }
    final iterations = ByteData.sublistView(
      Uint8List.fromList(bytes.sublist(5, 9)),
    ).getUint32(0);
    if (iterations < 1) {
      throw const BundleFormatException('invalid iteration count');
    }
    final salt = bytes.sublist(9, _headerLength);
    final cipher = SessionCipher(await _key(password, salt, iterations));
    final List<int> plaintext;
    try {
      plaintext = await cipher.open(bytes.sublist(_headerLength));
    } on TamperedMessageException {
      throw const WrongPasswordException();
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(plaintext));
    } on FormatException {
      throw const BundleFormatException('bundle payload is not JSON');
    }
    if (json is! Map || json['nodeId'] is! String || json['changes'] is! List) {
      throw const BundleFormatException('bundle payload is incomplete');
    }
    return BundleContents(
      nodeId: json['nodeId'] as String,
      changes: [
        for (final change in json['changes'] as List)
          Change.fromJson((change as Map).cast()),
      ],
    );
  }

  /// A suggested file name, from the newest change it carries.
  static String fileName(Hlc? latest) =>
      'vorsorge-${latest?.millis ?? 0}.$fileExtension';

  static Future<List<int>> _key(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final key = await Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    return key.extractBytes();
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}
