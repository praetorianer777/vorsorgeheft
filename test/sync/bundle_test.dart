import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/sync/bundle.dart';
import 'package:vorsorgereminder/sync/change.dart';
import 'package:vorsorgereminder/sync/hlc.dart';

void main() {
  final changes = [
    Change(
      entity: 'person',
      entityId: 'anna',
      field: 'name',
      hlc: Hlc(millis: 1000, counter: 0, nodeId: 'alice'),
      value: 'Anna',
    ),
    Change(
      entity: 'person',
      entityId: 'anna',
      field: Change.deletedField,
      hlc: Hlc(millis: 2000, counter: 3, nodeId: 'alice'),
      value: true,
    ),
  ];

  // Fewer rounds than the app uses: the point here is the format, and the
  // password stretching is the same code with a bigger number.
  const iterations = 1000;

  test('a bundle round-trips under the right password', () async {
    final bytes = await SyncBundle.seal(
      nodeId: 'alice',
      changes: changes,
      password: 'correct horse',
      iterations: iterations,
    );

    final contents = await SyncBundle.open(bytes, 'correct horse');
    expect(contents.nodeId, 'alice');
    expect(contents.changes.map((c) => c.key), changes.map((c) => c.key));
    expect(contents.changes.map((c) => c.hlc), changes.map((c) => c.hlc));
    expect(contents.changes.last.value, true);
  });

  test('the wrong password fails with a typed error', () async {
    final bytes = await SyncBundle.seal(
      nodeId: 'alice',
      changes: changes,
      password: 'correct horse',
      iterations: iterations,
    );
    expect(
      () => SyncBundle.open(bytes, 'battery staple'),
      throwsA(isA<WrongPasswordException>()),
    );
  });

  test('a file that is not a bundle is told apart from a wrong password', () {
    expect(
      () => SyncBundle.open([1, 2, 3], 'x'),
      throwsA(isA<BundleFormatException>()),
    );
  });

  test('the change set is not readable without the password', () async {
    final bytes = await SyncBundle.seal(
      nodeId: 'alice',
      changes: changes,
      password: 'correct horse',
      iterations: iterations,
    );
    expect(String.fromCharCodes(bytes), isNot(contains('Anna')));
    expect(String.fromCharCodes(bytes), isNot(contains('alice')));
  });

  test('the stretching the app ships with opens in reasonable time', () async {
    final started = DateTime.now();
    final bytes = await SyncBundle.seal(
      nodeId: 'alice',
      changes: changes,
      password: 'pw',
    );
    await SyncBundle.open(bytes, 'pw');
    expect(SyncBundle.defaultIterations, greaterThanOrEqualTo(100000));
    printOnFailure('took ${DateTime.now().difference(started)}');
  });
}
