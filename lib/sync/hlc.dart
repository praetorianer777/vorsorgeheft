/// A hybrid logical clock: wall time, a counter that breaks ties within the
/// same millisecond, and the id of the device that issued it.
///
/// Two phones that never talk to a server have no shared clock, and their
/// wall clocks drift. An HLC keeps causality intact anyway: receiving a remote
/// timestamp pushes the local clock past it, so a change made in reply to
/// another change always sorts after it, whatever the two devices think the
/// time is.
class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.millis,
    required this.counter,
    required this.nodeId,
  });

  /// The zero value for a node, ordering before any real timestamp. Used as
  /// the starting high-water mark for a peer nothing has been exchanged with.
  factory Hlc.zero(String nodeId) => Hlc(millis: 0, counter: 0, nodeId: nodeId);

  factory Hlc.now(String nodeId, DateTime wallClock) =>
      Hlc(millis: wallClock.millisecondsSinceEpoch, counter: 0, nodeId: nodeId);

  /// Parses the sortable encoding produced by [toString].
  factory Hlc.parse(String encoded) {
    final firstDash = encoded.indexOf('-');
    final secondDash = encoded.indexOf('-', firstDash + 1);
    if (firstDash < 0 || secondDash < 0) {
      throw FormatException('not an HLC: $encoded');
    }
    return Hlc(
      millis: int.parse(encoded.substring(0, firstDash)),
      counter: int.parse(
        encoded.substring(firstDash + 1, secondDash),
        radix: 16,
      ),
      nodeId: encoded.substring(secondDash + 1),
    );
  }

  final int millis;
  final int counter;
  final String nodeId;

  /// The largest counter a single millisecond can hold before the clock has to
  /// borrow from the next one. Overflowing it silently would let two changes
  /// share a timestamp and one of them vanish.
  static const maxCounter = 0xFFFF;

  /// The timestamp for a change made locally now.
  ///
  /// Wall clocks go backwards - a manual correction, a timezone database
  /// update, an NTP step - so the clock never moves back; it keeps the last
  /// millisecond and increments the counter instead.
  Hlc issue(DateTime wallClock) {
    final now = wallClock.millisecondsSinceEpoch;
    if (now > millis) return Hlc(millis: now, counter: 0, nodeId: nodeId);
    return _bumped(millis, counter + 1);
  }

  /// The local clock after seeing [remote].
  ///
  /// Moving past the remote timestamp is what keeps causality: a change made
  /// after receiving someone else's change sorts after it even if this device's
  /// wall clock is behind theirs.
  Hlc receive(Hlc remote, DateTime wallClock) {
    final now = wallClock.millisecondsSinceEpoch;
    final highest = [
      now,
      millis,
      remote.millis,
    ].reduce((a, b) => a > b ? a : b);

    if (highest == now && now > millis && now > remote.millis) {
      return Hlc(millis: now, counter: 0, nodeId: nodeId);
    }
    if (millis == remote.millis) {
      return _bumped(
        highest,
        (counter > remote.counter ? counter : remote.counter) + 1,
      );
    }
    if (highest == millis) return _bumped(highest, counter + 1);
    return _bumped(highest, remote.counter + 1);
  }

  Hlc _bumped(int atMillis, int nextCounter) => nextCounter > maxCounter
      ? Hlc(millis: atMillis + 1, counter: 0, nodeId: nodeId)
      : Hlc(millis: atMillis, counter: nextCounter, nodeId: nodeId);

  /// Encoded so that lexicographic order is timestamp order, which lets the
  /// database find everything newer than a peer's high-water mark with a plain
  /// string comparison on an indexed column.
  @override
  String toString() =>
      '${millis.toString().padLeft(15, '0')}'
      '-${counter.toRadixString(16).padLeft(4, '0')}'
      '-$nodeId';

  @override
  int compareTo(Hlc other) {
    final byMillis = millis.compareTo(other.millis);
    if (byMillis != 0) return byMillis;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);
}
