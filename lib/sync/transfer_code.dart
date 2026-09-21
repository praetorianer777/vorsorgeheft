import 'dart:math';

/// The six digits a person reads off one phone and types on the other.
///
/// Six digits are weak against an offline guess: a million tries is nothing
/// against a file someone kept. What makes it tolerable is that the file
/// exists only as long as the transfer, and that every try costs the full
/// PBKDF2 stretching the bundle format prescribes, which at the shipped
/// round count already takes about half a second on a desktop and so cannot
/// be raised much further before a phone keeps the person waiting. A copy
/// meant to last belongs under a real password, which is why the password
/// export stays next to this one.
class TransferCode {
  const TransferCode._();

  static const length = 6;

  /// A fresh code, zero-padded so that a code below 100000 keeps its six
  /// digits on screen and on the keypad.
  static String generate({Random? random}) {
    final value = (random ?? Random.secure()).nextInt(1000000);
    return value.toString().padLeft(length, '0');
  }

  static bool isWellFormed(String value) =>
      value.length == length && RegExp(r'^\d{6}$').hasMatch(value);
}
