import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/sync/session_cipher.dart';

void main() {
  final key = SecretKeyData.random(length: 32).bytes;

  test('a sealed message opens under the same key', () async {
    final cipher = SessionCipher(key);
    final sealed = await cipher.seal(utf8.encode('hello'));
    expect(utf8.decode(await cipher.open(sealed)), 'hello');
  });

  test('sealing the same message twice never repeats the ciphertext', () async {
    final cipher = SessionCipher(key);
    final first = await cipher.seal(utf8.encode('hello'));
    final second = await cipher.seal(utf8.encode('hello'));
    expect(first, isNot(second));
  });

  test(
    'a tampered message fails authentication instead of decrypting',
    () async {
      final cipher = SessionCipher(key);
      final sealed = await cipher.seal(utf8.encode('hello'));

      for (final position in [0, 12, sealed.length - 1]) {
        final tampered = List<int>.from(sealed);
        tampered[position] ^= 0x01;
        expect(
          () => cipher.open(tampered),
          throwsA(isA<TamperedMessageException>()),
          reason: 'byte $position',
        );
      }
    },
  );

  test('a message sealed under another key does not open', () async {
    final sealed = await SessionCipher(key).seal(utf8.encode('hello'));
    final other = SessionCipher(SecretKeyData.random(length: 32).bytes);
    expect(() => other.open(sealed), throwsA(isA<TamperedMessageException>()));
  });

  test('something too short to be a message is rejected', () {
    expect(
      () => SessionCipher(key).open([1, 2, 3]),
      throwsA(isA<TamperedMessageException>()),
    );
  });
}
