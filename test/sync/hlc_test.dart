import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/sync/hlc.dart';

void main() {
  DateTime at(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

  group('issuing', () {
    test('follows the wall clock forwards', () {
      final clock = Hlc.now('a', at(1000));
      expect(clock.issue(at(2000)).millis, 2000);
      expect(clock.issue(at(2000)).counter, 0);
    });

    test('never moves backwards when the wall clock does', () {
      // A manual correction, a timezone update or an NTP step can move a
      // phone's clock back. Following it would let a later change sort before
      // an earlier one and quietly lose it.
      final clock = Hlc(millis: 5000, counter: 3, nodeId: 'a');
      final next = clock.issue(at(1000));
      expect(next.millis, 5000);
      expect(next.counter, 4);
      expect(next > clock, isTrue);
    });

    test('two changes in the same millisecond still order', () {
      final first = Hlc.now('a', at(1000)).issue(at(1000));
      final second = first.issue(at(1000));
      expect(second > first, isTrue);
    });

    test('a full counter borrows from the next millisecond', () {
      final clock = Hlc(millis: 1000, counter: Hlc.maxCounter, nodeId: 'a');
      final next = clock.issue(at(1000));
      expect(next.millis, 1001);
      expect(next.counter, 0);
      expect(next > clock, isTrue);
    });
  });

  group('receiving', () {
    test('moves past a remote timestamp from the future', () {
      // Their clock is ahead of ours. Anything we do next is a reply to what
      // they sent, so it has to sort after it.
      final local = Hlc.now('a', at(1000));
      final remote = Hlc.now('b', at(9000));
      final after = local.receive(remote, at(1000));
      expect(after > remote, isTrue);
      expect(after.nodeId, 'a');
    });

    test('keeps the local clock when it is already ahead', () {
      final local = Hlc(millis: 9000, counter: 2, nodeId: 'a');
      final remote = Hlc.now('b', at(1000));
      final after = local.receive(remote, at(1000));
      expect(after.millis, 9000);
      expect(after > local, isTrue);
    });

    test('breaks a tie in the same millisecond', () {
      final local = Hlc(millis: 5000, counter: 1, nodeId: 'a');
      final remote = Hlc(millis: 5000, counter: 7, nodeId: 'b');
      final after = local.receive(remote, at(5000));
      expect(after.counter, 8);
      expect(after > remote, isTrue);
    });
  });

  group('ordering', () {
    test('the node id decides only when time and counter are equal', () {
      final a = Hlc(millis: 1, counter: 1, nodeId: 'a');
      final b = Hlc(millis: 1, counter: 1, nodeId: 'b');
      expect(a < b, isTrue);
      expect(Hlc(millis: 2, counter: 0, nodeId: 'a') > b, isTrue);
    });

    test('the encoding sorts the same way the clock does', () {
      // The database finds a peer's delta with a string comparison on an
      // indexed column, so the two orders have to agree exactly.
      final clocks = [
        Hlc(millis: 999, counter: 0, nodeId: 'z'),
        Hlc(millis: 1000, counter: 0, nodeId: 'a'),
        Hlc(millis: 1000, counter: 15, nodeId: 'a'),
        Hlc(millis: 1000, counter: 15, nodeId: 'b'),
        Hlc(millis: 100000, counter: 0, nodeId: 'a'),
      ];
      final byClock = [...clocks]..sort();
      final byString = [...clocks]
        ..sort((x, y) => x.toString().compareTo(y.toString()));
      expect(
        byString.map((c) => c.toString()),
        byClock.map((c) => c.toString()),
      );
    });

    test('round-trips through its encoding', () {
      final clock = Hlc(millis: 1726829400000, counter: 258, nodeId: 'phone-1');
      expect(Hlc.parse(clock.toString()), clock);
    });

    test('a string that is not a timestamp is refused', () {
      // It is read from what a peer sent or from a transfer file, so it is
      // not necessarily something this app wrote.
      for (final broken in [
        '',
        'nonsense',
        '1726829400000',
        '1726829400000-258',
      ]) {
        expect(() => Hlc.parse(broken), throwsFormatException, reason: broken);
      }
    });

    test('zero orders before everything', () {
      expect(Hlc.zero('a') < Hlc.now('a', at(1)), isTrue);
    });
  });
}
