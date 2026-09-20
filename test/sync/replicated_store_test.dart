import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/data/database.dart';
import 'package:vorsorgereminder/data/database_provider.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/sync/hlc.dart';
import 'package:vorsorgereminder/sync/replicated_store.dart';

/// A device: its own database, its own node id, its own clock.
class Replica {
  Replica._(this.name, this.db, this.store, this._clock);

  static Future<Replica> open(String name, {DateTime? startAt}) async {
    final db = openInMemoryDatabase();
    final clock = _Clock(startAt ?? DateTime.utc(2026, 9, 20));
    final store = await ReplicatedStore.open(
      db,
      nodeId: name,
      clock: clock.read,
    );
    return Replica._(name, db, store, clock);
  }

  final String name;
  final AppDatabase db;
  final ReplicatedStore store;
  final _Clock _clock;

  void advance(Duration by) => _clock.advance(by);

  Future<void> close() => db.close();

  /// Sends everything this replica knows to [other], the way a full sync
  /// would. Sending everything rather than a delta is deliberate here: a
  /// merge that is only correct for deltas is not correct.
  Future<void> sendAllTo(Replica other) async {
    await other.store.merge(await store.changesSince(Hlc.zero(name)));
  }
}

class _Clock {
  _Clock(this._now);

  DateTime _now;

  DateTime read() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

Future<void> exchange(Replica a, Replica b) async {
  await a.sendAllTo(b);
  await b.sendAllTo(a);
}

void main() {
  late Replica alice;

  setUp(() async => alice = await Replica.open('alice'));
  tearDown(() => alice.close());

  final anna = Person(
    id: 'anna',
    name: 'Anna',
    dateOfBirth: DateTime.utc(2026, 1, 15),
    sex: Sex.female,
  );

  group('local writes', () {
    test('a saved person shows up in the projection', () async {
      await alice.store.savePerson(anna);
      final stored = await alice.db.personById('anna');
      expect(stored!.name, 'Anna');
      expect(stored.dateOfBirth, DateTime.utc(2026, 1, 15));
      expect(stored.sex, Sex.female);
    });

    test('every field of a write is recorded separately', () async {
      await alice.store.savePerson(anna);
      final changes = await alice.db.changesFor('person', 'anna');
      expect(changes.map((c) => c.field).toSet(), {
        'name',
        'dateOfBirth',
        'sex',
        'notes',
      });
    });

    test('a deleted person leaves the projection but not the log', () async {
      await alice.store.savePerson(anna);
      await alice.store.deletePerson('anna');

      expect(await alice.db.personById('anna'), isNull);
      final changes = await alice.db.changesFor('person', 'anna');
      expect(changes.any((c) => c.isDeletion), isTrue);
    });

    test('completions project back to typed rows', () async {
      await alice.store.savePerson(anna);
      await alice.store.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'sixfold',
          doseId: '2',
          completedOn: DateTime.utc(2026, 5, 10),
          note: 'linker Arm',
        ),
      );
      final stored = (await alice.db.allCompletions()).single;
      expect(stored.ruleId, 'sixfold');
      expect(stored.doseId, '2');
      expect(stored.completedOn, DateTime.utc(2026, 5, 10));
      expect(stored.note, 'linker Arm');
    });

    test('clearing a completion removes it from the projection', () async {
      await alice.store.savePerson(anna);
      await alice.store.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      await alice.store.clearCompletion(personId: 'anna', ruleId: 'u6');
      expect(await alice.db.allCompletions(), isEmpty);
    });

    test('timestamps never repeat, even within one millisecond', () async {
      await alice.store.savePerson(anna);
      await alice.store.savePerson(
        Person(id: 'anna', name: 'Anna B.', dateOfBirth: anna.dateOfBirth),
      );
      final stamps = (await alice.db.changesSince(
        Hlc.zero('alice'),
      )).map((c) => c.hlc.toString()).toList();
      expect(stamps.toSet(), hasLength(stamps.length));
    });
  });

  group('restarting', () {
    test('keeps the node id', () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final first = await ReplicatedStore.open(db);
      final second = await ReplicatedStore.open(db);
      expect(second.nodeId, first.nodeId);
    });

    test('never issues a timestamp that sorts before what it wrote', () async {
      // A restart that forgot the clock would re-issue timestamps a peer has
      // already seen, and the peer would ignore the new writes as stale.
      await alice.store.savePerson(anna);
      final before = await alice.store.latest;

      final reopened = await ReplicatedStore.open(
        alice.db,
        nodeId: 'alice',
        clock: () => DateTime.utc(2020),
      );
      await reopened.savePerson(
        Person(id: 'anna', name: 'Later', dateOfBirth: anna.dateOfBirth),
      );

      expect((await alice.db.latestHlc())! > before!, isTrue);
      expect((await alice.db.personById('anna'))!.name, 'Later');
    });
  });

  group('two replicas', () {
    late Replica bob;

    setUp(() async => bob = await Replica.open('bob'));
    tearDown(() => bob.close());

    test('a person created on one appears on the other', () async {
      await alice.store.savePerson(anna);
      await exchange(alice, bob);

      final onBob = await bob.db.personById('anna');
      expect(onBob!.name, 'Anna');
      expect(onBob.sex, Sex.female);
    });

    test('edits to different fields both survive', () async {
      await alice.store.savePerson(anna);
      await exchange(alice, bob);

      // Alice renames while Bob writes a note, neither having seen the other.
      alice.advance(const Duration(minutes: 1));
      bob.advance(const Duration(minutes: 1));
      await alice.store.savePerson(
        Person(
          id: 'anna',
          name: 'Anna B.',
          dateOfBirth: anna.dateOfBirth,
          sex: Sex.female,
        ),
      );
      await bob.store.savePerson(
        Person(
          id: 'anna',
          name: 'Anna',
          dateOfBirth: anna.dateOfBirth,
          sex: Sex.female,
          notes: 'Zwilling',
        ),
      );

      await exchange(alice, bob);

      for (final replica in [alice, bob]) {
        final person = await replica.db.personById('anna');
        expect(person!.notes, 'Zwilling', reason: replica.name);
      }
    });

    test('the later edit of one field wins on both', () async {
      await alice.store.savePerson(anna);
      await exchange(alice, bob);

      alice.advance(const Duration(minutes: 1));
      await alice.store.savePerson(
        Person(id: 'anna', name: 'From Alice', dateOfBirth: anna.dateOfBirth),
      );
      bob.advance(const Duration(minutes: 5));
      await bob.store.savePerson(
        Person(id: 'anna', name: 'From Bob', dateOfBirth: anna.dateOfBirth),
      );

      await exchange(alice, bob);

      for (final replica in [alice, bob]) {
        expect(
          (await replica.db.personById('anna'))!.name,
          'From Bob',
          reason: replica.name,
        );
      }
    });

    test('an appointment recorded on one settles it on the other', () async {
      await alice.store.savePerson(anna);
      await alice.store.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      await exchange(alice, bob);

      final onBob = (await bob.db.allCompletions()).single;
      expect(onBob.ruleId, 'u6');
      expect(onBob.completedOn, DateTime.utc(2026, 11, 2));
    });

    test('a deletion propagates', () async {
      await alice.store.savePerson(anna);
      await exchange(alice, bob);

      alice.advance(const Duration(minutes: 1));
      await alice.store.deletePerson('anna');
      await exchange(alice, bob);

      expect(await bob.db.personById('anna'), isNull);
    });

    test('an edit made after a deletion brings the person back', () async {
      // Bob has been offline for a week and deletes Anna; Alice has been
      // editing her all along. Losing Alice's week of edits to a stale delete
      // is the failure this guards against.
      await alice.store.savePerson(anna);
      await exchange(alice, bob);

      bob.advance(const Duration(minutes: 1));
      await bob.store.deletePerson('anna');

      alice.advance(const Duration(days: 7));
      await alice.store.savePerson(
        Person(id: 'anna', name: 'Anna B.', dateOfBirth: anna.dateOfBirth),
      );

      await exchange(alice, bob);

      for (final replica in [alice, bob]) {
        final person = await replica.db.personById('anna');
        expect(person?.name, 'Anna B.', reason: replica.name);
      }
    });

    test('syncing twice changes nothing the second time', () async {
      await alice.store.savePerson(anna);
      await exchange(alice, bob);
      final applied = await bob.store.merge(
        await alice.store.changesSince(Hlc.zero('alice')),
      );
      expect(applied, isEmpty);
    });

    test('a delta carries only what the peer has not seen', () async {
      await alice.store.savePerson(anna);
      final watermark = (await alice.store.latest)!;

      alice.advance(const Duration(minutes: 1));
      await alice.store.savePerson(
        Person(id: 'mila', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
      );

      final delta = await alice.store.changesSince(watermark);
      expect(delta.map((c) => c.entityId).toSet(), {'mila'});
      expect(delta, isNotEmpty);
    });

    test(
      'a replica that has never synced catches up in one exchange',
      () async {
        // Distinct dates of birth, because the projection orders by them and
        // a tie would make this assert something the code never promised.
        const born = {'anna': 2020, 'mila': 2022, 'jonas': 2024};
        for (final entry in born.entries) {
          alice.advance(const Duration(seconds: 1));
          await alice.store.savePerson(
            Person(
              id: entry.key,
              name: entry.key,
              dateOfBirth: DateTime.utc(entry.value, 1, 1),
            ),
          );
        }
        await exchange(alice, bob);
        expect((await bob.db.allPersons()).map((p) => p.id), [
          'anna',
          'mila',
          'jonas',
        ]);
      },
    );

    test('a clock behind the peer still orders replies after them', () async {
      // Bob's phone is a day slow. His reply to Alice's edit must still win,
      // or the app would silently drop whatever he did last.
      final slowBob = await Replica.open(
        'slow-bob',
        startAt: DateTime.utc(2026, 9, 19),
      );
      addTearDown(slowBob.close);

      await alice.store.savePerson(anna);
      await exchange(alice, slowBob);

      await slowBob.store.savePerson(
        Person(id: 'anna', name: 'From Bob', dateOfBirth: anna.dateOfBirth),
      );
      await exchange(alice, slowBob);

      expect((await alice.db.personById('anna'))!.name, 'From Bob');
    });
  });
}
