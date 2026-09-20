import 'package:drift/drift.dart';

import '../domain/completion.dart' as domain;
import '../domain/person.dart' as domain;
import '../sync/change.dart';
import '../sync/hlc.dart';

part 'database.g.dart';

@DataClassName('PersonRow')
class Persons extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Stored as a UTC instant. Only the newborn screenings care about the time
  /// of day, so a person created without one gets midnight.
  DateTimeColumn get dateOfBirth => dateTime()();

  IntColumn get sex => intEnum<domain.Sex>()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CompletionRow')
class Completions extends Table {
  TextColumn get personId =>
      text().references(Persons, #id, onDelete: KeyAction.cascade)();
  TextColumn get ruleId => text()();

  /// Empty for anything that is not a vaccination series. SQLite treats two
  /// NULLs in a primary key as distinct, so a nullable column here would let
  /// the same appointment be recorded twice instead of edited.
  TextColumn get doseId => text().withDefault(const Constant(''))();
  DateTimeColumn get completedOn => dateTime()();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  /// One record per person, rule and dose: recording the same appointment twice
  /// is an edit, not a second appointment.
  @override
  Set<Column<Object>> get primaryKey => {personId, ruleId, doseId};
}

/// Device-local key/value settings.
///
/// Deliberately separate from anything the sync in #10 replicates: the locale
/// override and the support-prompt flag belong to this device, not to the
/// family.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The replicated state: one row per record field, holding the winning value
/// and the timestamp it was written at.
///
/// This is the source of truth that syncs. The persons and completions tables
/// are a projection of it, kept only so the rest of the app can read typed
/// rows without knowing replication exists.
@DataClassName('ChangeRow')
class Changes extends Table {
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get field => text()();

  /// The hybrid logical clock, in its sortable encoding, so a peer's delta is
  /// a plain string comparison on an indexed column.
  TextColumn get hlc => text()();

  /// JSON, so a value can be a string, a number, a bool or null without the
  /// column having to know which.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {entity, entityId, field};
}

@DriftDatabase(tables: [Persons, Completions, Settings, Changes])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Dates are stored as ISO-8601 text rather than unix seconds, which is what
  /// keeps them UTC. With the default encoding every date came back in local
  /// time, and the whole schedule is computed in UTC.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  int get schemaVersion => 1;

  /// SQLite enforces foreign keys only when asked to, and without this a
  /// deleted person leaves their recorded appointments behind.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Stream<List<domain.Person>> watchPersons() =>
      (select(persons)
            ..orderBy([(p) => OrderingTerm(expression: p.dateOfBirth)]))
          .watch()
          .map((rows) => rows.map(_toPerson).toList());

  Future<List<domain.Person>> allPersons() async =>
      (await (select(
            persons,
          )..orderBy([(p) => OrderingTerm(expression: p.dateOfBirth)])).get())
          .map(_toPerson)
          .toList();

  Future<domain.Person?> personById(String id) async {
    final row = await (select(
      persons,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toPerson(row);
  }

  Future<void> upsertPerson(domain.Person person) =>
      into(persons).insertOnConflictUpdate(
        PersonsCompanion.insert(
          id: person.id,
          name: person.name,
          dateOfBirth: person.dateOfBirth,
          sex: person.sex,
          notes: Value(person.notes),
        ),
      );

  Future<void> deletePerson(String id) =>
      (delete(persons)..where((p) => p.id.equals(id))).go();

  Stream<List<domain.Completion>> watchCompletions() => select(
    completions,
  ).watch().map((rows) => rows.map(_toCompletion).toList());

  Future<List<domain.Completion>> allCompletions() async =>
      (await select(completions).get()).map(_toCompletion).toList();

  Future<void> recordCompletion(domain.Completion completion) =>
      into(completions).insertOnConflictUpdate(
        CompletionsCompanion.insert(
          personId: completion.personId,
          ruleId: completion.ruleId,
          doseId: Value(completion.doseId ?? ''),
          completedOn: completion.completedOn,
          skipped: Value(completion.skipped),
          note: Value(completion.note),
        ),
      );

  Future<void> clearCompletion({
    required String personId,
    required String ruleId,
    String? doseId,
  }) =>
      (delete(completions)..where(
            (c) =>
                c.personId.equals(personId) &
                c.ruleId.equals(ruleId) &
                c.doseId.equals(doseId ?? ''),
          ))
          .go();

  Future<List<Change>> changesSince(Hlc watermark) async {
    final rows =
        await (select(changes)
              ..where((c) => c.hlc.isBiggerThanValue(watermark.toString()))
              ..orderBy([(c) => OrderingTerm(expression: c.hlc)]))
            .get();
    return rows.map(_toChange).toList();
  }

  Future<List<Change>> changesFor(String entity, String entityId) async {
    final rows =
        await (select(changes)..where(
              (c) => c.entity.equals(entity) & c.entityId.equals(entityId),
            ))
            .get();
    return rows.map(_toChange).toList();
  }

  Future<Hlc?> latestHlc() async {
    final row =
        await (select(changes)
              ..orderBy([
                (c) => OrderingTerm(expression: c.hlc, mode: OrderingMode.desc),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : Hlc.parse(row.hlc);
  }

  /// Writes the changes that beat what is already stored, and returns them.
  ///
  /// The comparison happens here rather than in Dart so that a concurrent
  /// write cannot slip between reading the current value and deciding.
  Future<List<Change>> applyChanges(Iterable<Change> incoming) =>
      transaction(() async {
        final applied = <Change>[];
        for (final change in incoming) {
          final existing =
              await (select(changes)..where(
                    (c) =>
                        c.entity.equals(change.entity) &
                        c.entityId.equals(change.entityId) &
                        c.field.equals(change.field),
                  ))
                  .getSingleOrNull();

          if (existing != null && change.hlc <= Hlc.parse(existing.hlc)) {
            continue;
          }
          await into(changes).insertOnConflictUpdate(
            ChangesCompanion.insert(
              entity: change.entity,
              entityId: change.entityId,
              field: change.field,
              hlc: change.hlc.toString(),
              value: change.encodeValue(),
            ),
          );
          applied.add(change);
        }
        return applied;
      });

  Future<String?> settingValue(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) => into(
    settings,
  ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

Change _toChange(ChangeRow row) => Change(
  entity: row.entity,
  entityId: row.entityId,
  field: row.field,
  hlc: Hlc.parse(row.hlc),
  value: Change.decodeValue(row.value),
);

domain.Person _toPerson(PersonRow row) => domain.Person(
  id: row.id,
  name: row.name,
  dateOfBirth: row.dateOfBirth,
  sex: row.sex,
  notes: row.notes,
);

domain.Completion _toCompletion(CompletionRow row) => domain.Completion(
  personId: row.personId,
  ruleId: row.ruleId,
  doseId: row.doseId.isEmpty ? null : row.doseId,
  completedOn: row.completedOn,
  skipped: row.skipped,
  note: row.note,
);
