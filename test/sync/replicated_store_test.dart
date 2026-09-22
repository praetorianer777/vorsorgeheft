import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/own_appointment.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/sync/hlc.dart';
import 'package:vorsorgeheft/sync/overwrite_notice.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';

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
  Future<MergeResult> sendAllTo(Replica other) async {
    return other.store.merge(
      await store.changesSince(Hlc.zero(name)),
      from: name,
    );
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
        'optionalRules',
      });
    });

    test('the optional rules a person switched on round-trip', () async {
      await alice.store.savePerson(
        Person(
          id: 'anna',
          name: 'Anna',
          dateOfBirth: DateTime.utc(1990, 1, 15),
          optionalRules: const {'tbe', 'influenza-under-60'},
        ),
      );
      final stored = await alice.db.personById('anna');
      expect(stored!.optionalRules, {'influenza-under-60', 'tbe'});

      await alice.store.savePerson(anna);
      expect((await alice.db.personById('anna'))!.optionalRules, isEmpty);
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

    test('an own appointment projects to its row and can be removed', () async {
      await alice.store.savePerson(anna);
      final eyes = OwnAppointment(
        id: 'eyes',
        personId: 'anna',
        title: 'Eye check',
        firstOn: DateTime.utc(2026, 11, 3),
        everyMonths: 12,
        note: 'bring the glasses',
      );
      await alice.store.saveOwnAppointment(eyes);
      expect(await alice.db.allOwnAppointments(), [eyes]);

      await alice.store.saveOwnAppointment(eyes.copyWith(everyMonths: 6));
      expect((await alice.db.allOwnAppointments()).single.everyMonths, 6);

      await alice.store.deleteOwnAppointment('eyes');
      expect(await alice.db.allOwnAppointments(), isEmpty);
    });

    test('the family name projects to its row', () async {
      await alice.store.saveFamilyName('  Familie Meier ');
      expect(await alice.db.familyName('family'), 'Familie Meier');
      final change = (await alice.db.changesFor('family', 'family')).single;
      expect(change.field, 'name');
      expect(change.value, 'Familie Meier');
    });

    test('a blank name clears it but keeps the record', () async {
      await alice.store.saveFamilyName('Familie Meier');
      await alice.store.saveFamilyName('   ');
      expect(await alice.db.familyName('family'), isNull);
      expect(await alice.db.changesFor('family', 'family'), hasLength(1));
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

    test('the family name reaches the other, and the later one wins', () async {
      await alice.store.saveFamilyName('Familie Meier');
      await exchange(alice, bob);
      expect(await bob.db.familyName('family'), 'Familie Meier');

      alice.advance(const Duration(minutes: 1));
      await alice.store.saveFamilyName('Haus Sonnenschein');
      bob.advance(const Duration(minutes: 5));
      await bob.store.saveFamilyName('');
      await exchange(alice, bob);

      for (final replica in [alice, bob]) {
        expect(
          await replica.db.familyName('family'),
          isNull,
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

    test('an own appointment reaches the other phone', () async {
      await alice.store.savePerson(anna);
      final eyes = OwnAppointment(
        id: 'eyes',
        personId: 'anna',
        title: 'Eye check',
        firstOn: DateTime.utc(2026, 11, 3),
        everyMonths: 12,
      );
      await alice.store.saveOwnAppointment(eyes);
      await exchange(alice, bob);
      expect(await bob.db.allOwnAppointments(), [eyes]);

      bob.advance(const Duration(minutes: 1));
      await bob.store.deleteOwnAppointment('eyes');
      await exchange(alice, bob);
      expect(await alice.db.allOwnAppointments(), isEmpty);
    });

    test(
      'an own appointment for a person deleted meanwhile is dropped',
      () async {
        await alice.store.savePerson(anna);
        await exchange(alice, bob);
        bob.advance(const Duration(minutes: 1));
        await bob.store.deletePerson('anna');
        alice.advance(const Duration(seconds: 30));
        await alice.store.saveOwnAppointment(
          OwnAppointment(
            id: 'eyes',
            personId: 'anna',
            title: 'Eye check',
            firstOn: DateTime.utc(2026, 11, 3),
            everyMonths: 12,
          ),
        );
        await exchange(alice, bob);
        expect(await bob.db.allPersons(), isEmpty);
        expect(await bob.db.allOwnAppointments(), isEmpty);
      },
    );

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
      final result = await bob.store.merge(
        await alice.store.changesSince(Hlc.zero('alice')),
      );
      expect(result.applied, isEmpty);
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

  group('the same appointment recorded on both phones', () {
    late Replica bob;

    // Both phones know Anna before either records anything for her, the way
    // they would after the first sync.
    setUp(() async {
      bob = await Replica.open('bob');
      await alice.store.savePerson(anna);
      await exchange(alice, bob);
    });
    tearDown(() => bob.close());

    Completion u6({required DateTime on, bool skipped = false}) => Completion(
      personId: 'anna',
      ruleId: 'u6',
      completedOn: on,
      skipped: skipped,
    );

    Future<List<OverwriteNotice>> notices(Replica replica) =>
        replica.store.watchNotices().first;

    test('the phone whose entry lost is told, the other one is not', () async {
      await alice.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));
      bob.advance(const Duration(hours: 1));
      await bob.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 4)));

      final atBob = await alice.sendAllTo(bob);
      final atAlice = await bob.sendAllTo(alice);

      expect(atBob.overwritten, isEmpty);
      expect(await notices(bob), isEmpty);

      final notice = atAlice.overwritten.single;
      expect(notice.personId, 'anna');
      expect(notice.ruleId, 'u6');
      expect(notice.previousDate, DateTime.utc(2027, 3, 3));
      expect(notice.currentDate, DateTime.utc(2027, 3, 4));
      expect(notice.fromNodeId, 'bob');
      expect(
        (await alice.db.allCompletions()).single.completedOn,
        DateTime.utc(2027, 3, 4),
      );
      expect((await notices(alice)).single.currentDate, notice.currentDate);
    });

    test('the same date on both phones is no conflict', () async {
      await alice.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));
      bob.advance(const Duration(hours: 1));
      await bob.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));

      final atAlice = await bob.sendAllTo(alice);
      expect(atAlice.overwritten, isEmpty);
      expect(await notices(alice), isEmpty);
    });

    test('an undo on the other phone is reported as removed', () async {
      await alice.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));
      await exchange(alice, bob);
      bob.advance(const Duration(hours: 1));
      await bob.store.clearCompletion(personId: 'anna', ruleId: 'u6');

      final atAlice = await bob.sendAllTo(alice);
      final notice = atAlice.overwritten.single;
      expect(notice.removed, isTrue);
      expect(notice.previousDate, DateTime.utc(2027, 3, 3));
      expect(await alice.db.allCompletions(), isEmpty);
    });

    test('a switch from done to skipped is reported too', () async {
      await alice.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));
      bob.advance(const Duration(hours: 1));
      await bob.store.recordCompletion(
        u6(on: DateTime.utc(2027, 3, 3), skipped: true),
      );

      final atAlice = await bob.sendAllTo(alice);
      final notice = atAlice.overwritten.single;
      expect(notice.previousSkipped, isFalse);
      expect(notice.currentSkipped, isTrue);
    });

    test("an entry the other phone made is theirs to change", () async {
      // Alice never recorded the U6 herself; Bob did, and Bob corrects it.
      // Only an entry this phone made counts as "yours".
      await bob.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));
      await exchange(alice, bob);
      bob.advance(const Duration(hours: 1));
      await bob.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 5)));

      final atAlice = await bob.sendAllTo(alice);
      expect(atAlice.overwritten, isEmpty);
    });

    test('a renamed child is an edit, not a conflict', () async {
      bob.advance(const Duration(hours: 1));
      await bob.store.savePerson(
        Person(id: 'anna', name: 'Anna B.', dateOfBirth: anna.dateOfBirth),
      );

      final atAlice = await bob.sendAllTo(alice);
      expect(atAlice.overwritten, isEmpty);
    });

    test('notices accumulate until cleared, and survive a restart', () async {
      await alice.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 3)));
      bob.advance(const Duration(hours: 1));
      await bob.store.recordCompletion(u6(on: DateTime.utc(2027, 3, 4)));
      await bob.sendAllTo(alice);

      final reopened = await ReplicatedStore.open(alice.db, nodeId: 'alice');
      expect(await reopened.watchNotices().first, hasLength(1));

      await reopened.clearNotices();
      expect(await reopened.watchNotices().first, isEmpty);
    });
  });
}
