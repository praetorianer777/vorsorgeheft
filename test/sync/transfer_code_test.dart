import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/sync/transfer_code.dart';

void main() {
  test('a code is six digits', () {
    for (var i = 0; i < 200; i++) {
      expect(TransferCode.generate(), matches(RegExp(r'^\d{6}$')));
    }
  });

  test('a small number keeps its leading zeros', () {
    expect(TransferCode.generate(random: _Fixed(7)), '000007');
    expect(TransferCode.generate(random: _Fixed(0)), '000000');
    expect(TransferCode.generate(random: _Fixed(999999)), '999999');
  });

  test('only six digits count as a code', () {
    expect(TransferCode.isWellFormed('000007'), isTrue);
    expect(TransferCode.isWellFormed('7'), isFalse);
    expect(TransferCode.isWellFormed('1234567'), isFalse);
    expect(TransferCode.isWellFormed('12345a'), isFalse);
    expect(TransferCode.isWellFormed('12 345'), isFalse);
  });
}

class _Fixed implements Random {
  _Fixed(this.value);

  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
