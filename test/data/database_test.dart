import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/data/database.dart';
import 'package:vorsorgereminder/data/database_provider.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/person.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());

  final anna = Person(
    id: 'anna',
    name: 'Anna',
    dateOfBirth: DateTime.utc(2026, 1, 15),
    sex: Sex.female,
    notes: 'Zwilling',
  );

  test('a person round-trips with every field intact', () async {
    await db.upsertPerson(anna);
    final stored = await db.personById('anna');
    expect(stored!.name, 'Anna');
    expect(stored.dateOfBirth, DateTime.utc(2026, 1, 15));
    expect(stored.sex, Sex.female);
    expect(stored.notes, 'Zwilling');
  });

  test('saving the same id twice edits rather than duplicates', () async {
    await db.upsertPerson(anna);
    await db.upsertPerson(
      Person(id: 'anna', name: 'Anna B.', dateOfBirth: anna.dateOfBirth),
    );
    final all = await db.allPersons();
    expect(all, hasLength(1));
    expect(all.single.name, 'Anna B.');
    expect(all.single.sex, Sex.notStated);
  });

  test('persons come back oldest first', () async {
    await db.upsertPerson(anna);
    await db.upsertPerson(
      Person(id: 'papa', name: 'Papa', dateOfBirth: DateTime.utc(1985, 3, 1)),
    );
    expect((await db.allPersons()).map((p) => p.id), ['papa', 'anna']);
  });

  group('completions', () {
    setUp(() => db.upsertPerson(anna));

    test('round-trip a completion without a dose', () async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      final stored = (await db.allCompletions()).single;
      expect(stored.ruleId, 'u6');
      expect(stored.doseId, isNull);
      expect(stored.skipped, isFalse);
    });

    test('doses of one rule are separate records', () async {
      for (final dose in ['1', '2']) {
        await db.recordCompletion(
          Completion(
            personId: 'anna',
            ruleId: 'sixfold',
            doseId: dose,
            completedOn: DateTime.utc(2026, 3, 1),
          ),
        );
      }
      expect(await db.allCompletions(), hasLength(2));
    });

    test('recording the same appointment twice is an edit', () async {
      for (final date in [
        DateTime.utc(2026, 11, 2),
        DateTime.utc(2026, 11, 9),
      ]) {
        await db.recordCompletion(
          Completion(personId: 'anna', ruleId: 'u6', completedOn: date),
        );
      }
      final all = await db.allCompletions();
      expect(all, hasLength(1));
      expect(all.single.completedOn, DateTime.utc(2026, 11, 9));
    });

    // A null dose id is not equal to anything in SQL, so clearing a completion
    // that has none needs an IS NULL rather than an equality test.
    test('clearing a completion without a dose finds it', () async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      await db.clearCompletion(personId: 'anna', ruleId: 'u6');
      expect(await db.allCompletions(), isEmpty);
    });

    test('clearing one dose leaves the others', () async {
      for (final dose in ['1', '2']) {
        await db.recordCompletion(
          Completion(
            personId: 'anna',
            ruleId: 'sixfold',
            doseId: dose,
            completedOn: DateTime.utc(2026, 3, 1),
          ),
        );
      }
      await db.clearCompletion(
        personId: 'anna',
        ruleId: 'sixfold',
        doseId: '1',
      );
      expect((await db.allCompletions()).single.doseId, '2');
    });

    test('deleting a person takes their completions with them', () async {
      await db.recordCompletion(
        Completion(
          personId: 'anna',
          ruleId: 'u6',
          completedOn: DateTime.utc(2026, 11, 2),
        ),
      );
      await db.deletePerson('anna');
      expect(await db.allPersons(), isEmpty);
      expect(await db.allCompletions(), isEmpty);
    });
  });

  test('settings store and overwrite by key', () async {
    expect(await db.settingValue('locale'), isNull);
    await db.putSetting('locale', 'de');
    await db.putSetting('locale', 'en');
    expect(await db.settingValue('locale'), 'en');
  });
}
