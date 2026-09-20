import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/sync/change.dart';
import 'package:vorsorgereminder/sync/hlc.dart';

Change change(
  String field,
  Object? value, {
  required int millis,
  String node = 'a',
  String id = 'p1',
  int counter = 0,
  String entity = 'person',
}) => Change(
  entity: entity,
  entityId: id,
  field: field,
  hlc: Hlc(millis: millis, counter: counter, nodeId: node),
  value: value,
);

void main() {
  group('last write wins per field', () {
    test('the newer change replaces the older', () {
      final set = ChangeSet([
        change('name', 'Anna', millis: 1000),
        change('name', 'Anna B.', millis: 2000),
      ]);
      expect(set.record('person', 'p1'), {'name': 'Anna B.'});
    });

    test('an older change arriving late is ignored', () {
      final set = ChangeSet([
        change('name', 'Anna B.', millis: 2000),
        change('name', 'Anna', millis: 1000),
      ]);
      expect(set.record('person', 'p1'), {'name': 'Anna B.'});
    });

    test('edits to different fields both survive', () {
      // One parent renames the child while the other records an appointment.
      // Replicating whole records would make the later write erase the other.
      final set = ChangeSet([
        change('name', 'Anna', millis: 1000, node: 'a'),
        change('notes', 'Zwilling', millis: 1100, node: 'b'),
      ]);
      expect(set.record('person', 'p1'), {'name': 'Anna', 'notes': 'Zwilling'});
    });

    test('a tie in the same millisecond is broken the same way everywhere', () {
      final fromA = change('name', 'A', millis: 1000, node: 'a');
      final fromB = change('name', 'B', millis: 1000, node: 'b');
      expect(ChangeSet([fromA, fromB]).record('person', 'p1'), {'name': 'B'});
      expect(ChangeSet([fromB, fromA]).record('person', 'p1'), {'name': 'B'});
    });
  });

  group('merging converges', () {
    final changes = [
      change('name', 'Anna', millis: 1000, node: 'a'),
      change('name', 'Anna B.', millis: 3000, node: 'b'),
      change('notes', 'x', millis: 2000, node: 'a'),
      change('notes', 'y', millis: 2500, node: 'b'),
      change('name', 'Mila', millis: 1500, node: 'a', id: 'p2'),
    ];

    Map<String, Object?> stateOf(ChangeSet set) => {
      for (final c in set.all) c.key: c.value,
    };

    test('order does not matter', () {
      final forwards = ChangeSet(changes);
      final backwards = ChangeSet(changes.reversed);
      expect(stateOf(backwards), stateOf(forwards));
    });

    test('repeats do not matter', () {
      final once = ChangeSet(changes);
      final twice = ChangeSet([...changes, ...changes, ...changes]);
      expect(stateOf(twice), stateOf(once));
    });

    test('grouping does not matter', () {
      final atOnce = ChangeSet(changes);
      final inBatches = ChangeSet()
        ..merge(changes.take(2))
        ..merge(changes.skip(2).take(1))
        ..merge(changes.skip(3));
      expect(stateOf(inBatches), stateOf(atOnce));
    });

    test('merge reports only what actually took effect', () {
      final set = ChangeSet([change('name', 'Anna', millis: 2000)]);
      expect(set.merge([change('name', 'Old', millis: 1000)]), isEmpty);
      expect(set.merge([change('name', 'New', millis: 3000)]), hasLength(1));
      expect(set.merge([change('name', 'New', millis: 3000)]), isEmpty);
    });

    test('two replicas converge over randomised histories', () {
      // The timestamps come from real clocks rather than random numbers: a
      // node never issues the same timestamp twice, and a test that pretends
      // otherwise is asserting convergence for a history that cannot happen.
      final random = Random(20260920);
      for (var run = 0; run < 200; run++) {
        final clocks = {'a': Hlc.zero('a'), 'b': Hlc.zero('b')};
        final history = <Change>[];
        for (var i = 0; i < 40; i++) {
          final node = ['a', 'b'][random.nextInt(2)];
          final wall = DateTime.fromMillisecondsSinceEpoch(
            1000 + random.nextInt(20),
          );
          final stamp = clocks[node] = clocks[node]!.issue(wall);
          history.add(
            Change(
              entity: 'person',
              entityId: ['p1', 'p2'][random.nextInt(2)],
              field: ['name', 'notes', 'sex'][random.nextInt(3)],
              hlc: stamp,
              value: random.nextInt(100),
            ),
          );
        }

        final left = ChangeSet(history);
        final right = ChangeSet(history.reversed);
        // Each replica also sees a stray repeat, as a lossy transport would.
        right.merge(history.take(5));
        left.merge(history.skip(30));
        expect(stateOf(right), stateOf(left), reason: 'run $run');
      }
    });
  });

  group('deletions', () {
    final deletion = change(Change.deletedField, true, millis: 2000);

    test('a deletion hides the record', () {
      final set = ChangeSet([change('name', 'Anna', millis: 1000), deletion]);
      expect(set.record('person', 'p1'), isNull);
    });

    test('a deletion beats an older edit whatever the order', () {
      final edit = change('name', 'Anna', millis: 1000);
      expect(ChangeSet([edit, deletion]).record('person', 'p1'), isNull);
      expect(ChangeSet([deletion, edit]).record('person', 'p1'), isNull);
    });

    test('an edit made after a deletion brings the record back', () {
      // Otherwise one parent deleting a person on a phone that has been
      // offline for a week would silently erase a week of the other parent's
      // edits when the two finally sync.
      final set = ChangeSet([
        change('name', 'Anna', millis: 1000),
        deletion,
        change('name', 'Anna B.', millis: 3000, node: 'b'),
      ]);
      expect(set.record('person', 'p1'), {'name': 'Anna B.'});
    });

    test('a record nobody ever wrote is absent, not deleted', () {
      expect(ChangeSet().record('person', 'nope'), isNull);
    });
  });

  group('deltas', () {
    test('since returns what a peer has not seen, in order', () {
      final set = ChangeSet([
        change('name', 'Anna', millis: 1000),
        change('notes', 'x', millis: 3000),
        change('sex', 'female', millis: 2000),
      ]);
      final delta = set.since(Hlc(millis: 1500, counter: 0, nodeId: 'a'));
      expect(delta.map((c) => c.field), ['sex', 'notes']);
    });

    test('a peer that is up to date gets nothing', () {
      final set = ChangeSet([change('name', 'Anna', millis: 1000)]);
      expect(set.since(set.latest!), isEmpty);
    });

    test('a peer that has seen nothing gets everything', () {
      final set = ChangeSet([
        change('name', 'Anna', millis: 1000),
        change('notes', 'x', millis: 2000),
      ]);
      expect(set.since(Hlc.zero('b')), hasLength(2));
    });
  });

  test('a change round-trips through JSON', () {
    final original = change('name', 'Anna', millis: 1726829400000, counter: 7);
    final restored = Change.fromJson(original.toJson());
    expect(restored.key, original.key);
    expect(restored.hlc, original.hlc);
    expect(restored.value, 'Anna');
  });

  test('a malformed change is rejected rather than half-read', () {
    expect(
      () => Change.fromJson({'entity': 'person', 'id': 'p1'}),
      throwsFormatException,
    );
  });
}
