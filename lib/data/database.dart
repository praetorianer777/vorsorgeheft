import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/completion.dart' as domain;
import '../domain/own_appointment.dart' as domain;
import '../domain/person.dart' as domain;
import '../sync/change.dart';
import '../sync/hlc.dart';
import '../sync/sync_protocol.dart';

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

  /// The switched-on optional rules as a comma-separated list of rule ids,
  /// null when there are none. See [encodeOptionalRules].
  TextColumn get optionalRules => text().nullable()();

  /// The [domain.Species] by name rather than by index, so adding a species
  /// can never turn an existing dog into something else. Every row written
  /// before pets existed is a person.
  TextColumn get species => text().withDefault(const Constant('human'))();

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

/// A person's own recurring appointments, projected from the change log like
/// persons and completions.
@DataClassName('OwnAppointmentRow')
class OwnAppointments extends Table {
  TextColumn get id => text()();
  TextColumn get personId =>
      text().references(Persons, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  DateTimeColumn get firstOn => dateTime()();
  IntColumn get everyMonths => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
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

/// The devices this one is paired with.
///
/// Device-local like [Settings]: a peer is a fact about this phone, and the
/// other phone keeps its own row for us. The shared key is stored as it is,
/// which is as protected as the rest of the database on the same device;
/// encrypting it at rest would need a platform keystore and is out of scope.
@DataClassName('PeerRow')
class Peers extends Table {
  TextColumn get nodeId => text()();
  TextColumn get deviceName => text()();

  /// Base64 of the 32-byte AES key both phones derived from the pairing.
  TextColumn get sharedKey => text()();

  /// The peer's high-water mark as of the last exchange, in the sortable
  /// encoding, or null before the first one.
  TextColumn get lastSyncHlc => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {nodeId};
}

/// The family's name, projected from the change log like [Persons].
///
/// A table of its own rather than a row in [Settings], because settings are
/// device-local and the name is the one thing on the start screen both parents
/// are meant to read the same way.
@DataClassName('FamilyRow')
class Families extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Persons,
    Completions,
    OwnAppointments,
    Settings,
    Changes,
    Peers,
    Families,
  ],
)
class AppDatabase extends _$AppDatabase implements PeerRegistry {
  AppDatabase(super.executor);

  /// Dates are stored as ISO-8601 text rather than unix seconds, which is what
  /// keeps them UTC. With the default encoding every date came back in local
  /// time, and the whole schedule is computed in UTC.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  /// Bumped for the peers table in #10, the families table in #46, the
  /// optional vaccinations in #70, the own appointments in #92 and the
  /// species in #96. An older database gains the tables and the columns in
  /// [migration]; everything it already holds stays as it is.
  @override
  int get schemaVersion => 6;

  /// SQLite enforces foreign keys only when asked to, and without this a
  /// deleted person leaves their recorded appointments behind.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(peers);
      if (from < 3) await m.createTable(families);
      if (from < 4) await m.addColumn(persons, persons.optionalRules);
      if (from < 5) await m.createTable(ownAppointments);
      if (from < 6) await m.addColumn(persons, persons.species);
    },
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
          optionalRules: Value(encodeOptionalRules(person.optionalRules)),
          species: Value(person.species.name),
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

  Stream<List<domain.OwnAppointment>> watchOwnAppointments() => select(
    ownAppointments,
  ).watch().map((rows) => rows.map(_toOwnAppointment).toList());

  Future<List<domain.OwnAppointment>> allOwnAppointments() async =>
      (await select(ownAppointments).get()).map(_toOwnAppointment).toList();

  Future<void> upsertOwnAppointment(domain.OwnAppointment appointment) =>
      into(ownAppointments).insertOnConflictUpdate(
        OwnAppointmentsCompanion.insert(
          id: appointment.id,
          personId: appointment.personId,
          title: appointment.title,
          firstOn: appointment.firstOn,
          everyMonths: appointment.everyMonths,
          note: Value(appointment.note),
        ),
      );

  Future<bool> hasPerson(String id) async =>
      await (select(
        persons,
      )..where((p) => p.id.equals(id))).getSingleOrNull() !=
      null;

  Future<void> deleteOwnAppointment(String id) =>
      (delete(ownAppointments)..where((a) => a.id.equals(id))).go();

  domain.OwnAppointment _toOwnAppointment(OwnAppointmentRow row) =>
      domain.OwnAppointment(
        id: row.id,
        personId: row.personId,
        title: row.title,
        firstOn: row.firstOn,
        everyMonths: row.everyMonths,
        note: row.note,
      );

  Stream<String?> watchFamilyName(String id) => (select(
    families,
  )..where((f) => f.id.equals(id))).watchSingleOrNull().map((row) => row?.name);

  Future<String?> familyName(String id) async {
    final row = await (select(
      families,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    return row?.name;
  }

  Future<void> upsertFamily(String id, String name) => into(
    families,
  ).insertOnConflictUpdate(FamiliesCompanion.insert(id: id, name: name));

  Future<void> deleteFamily(String id) =>
      (delete(families)..where((f) => f.id.equals(id))).go();

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

  Stream<String?> watchSetting(String key) =>
      (select(settings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  static const privateKeySettingKey = 'sync.private-key';
  static const deviceNameSettingKey = 'sync.device-name';

  Stream<List<Peer>> watchPeers() =>
      (select(peers)..orderBy([(p) => OrderingTerm(expression: p.deviceName)]))
          .watch()
          .map((rows) => rows.map(_toPeer).toList());

  @override
  Future<List<Peer>> allPeers() async =>
      (await (select(
            peers,
          )..orderBy([(p) => OrderingTerm(expression: p.deviceName)])).get())
          .map(_toPeer)
          .toList();

  @override
  Future<Peer?> peer(String nodeId) async {
    final row = await (select(
      peers,
    )..where((p) => p.nodeId.equals(nodeId))).getSingleOrNull();
    return row == null ? null : _toPeer(row);
  }

  @override
  Future<void> savePeer(Peer peer) => into(peers).insertOnConflictUpdate(
    PeersCompanion.insert(
      nodeId: peer.nodeId,
      deviceName: peer.deviceName,
      sharedKey: base64.encode(peer.sharedKey),
      lastSyncHlc: Value(peer.lastSyncHlc?.toString()),
      lastSyncAt: Value(peer.lastSyncAt),
    ),
  );

  @override
  Future<void> removePeer(String nodeId) =>
      (delete(peers)..where((p) => p.nodeId.equals(nodeId))).go();

  @override
  Future<void> recordSync(
    String nodeId, {
    required Hlc watermark,
    required DateTime at,
  }) => (update(peers)..where((p) => p.nodeId.equals(nodeId))).write(
    PeersCompanion(
      lastSyncHlc: Value(watermark.toString()),
      lastSyncAt: Value(at),
    ),
  );

  /// The X25519 private key. It is written once, read on every start and
  /// never sent anywhere; the pairing code carries only the public half.
  @override
  Future<List<int>?> privateKey() async {
    final stored = await settingValue(privateKeySettingKey);
    return stored == null ? null : base64.decode(stored);
  }

  @override
  Future<void> putPrivateKey(List<int> key) =>
      putSetting(privateKeySettingKey, base64.encode(key));

  @override
  Future<String?> deviceName() => settingValue(deviceNameSettingKey);

  @override
  Future<void> putDeviceName(String name) =>
      putSetting(deviceNameSettingKey, name);
}

Peer _toPeer(PeerRow row) => Peer(
  nodeId: row.nodeId,
  deviceName: row.deviceName,
  sharedKey: base64.decode(row.sharedKey),
  lastSyncHlc: row.lastSyncHlc == null ? null : Hlc.parse(row.lastSyncHlc!),
  lastSyncAt: row.lastSyncAt,
);

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
  optionalRules: decodeOptionalRules(row.optionalRules),
  species: domain.Species.parse(row.species),
);

/// Rule ids are lowercase ASCII with hyphens, so a comma-separated list is
/// unambiguous and reads the same in the change log and in the column. Sorted,
/// so the same choice always encodes to the same string and a sync does not
/// see a change where there is none; empty becomes null.
String? encodeOptionalRules(Set<String> ruleIds) =>
    ruleIds.isEmpty ? null : (ruleIds.toList()..sort()).join(',');

Set<String> decodeOptionalRules(String? encoded) => encoded == null
    ? const {}
    : {
        for (final id in encoded.split(','))
          if (id.isNotEmpty) id,
      };

domain.Completion _toCompletion(CompletionRow row) => domain.Completion(
  personId: row.personId,
  ruleId: row.ruleId,
  doseId: row.doseId.isEmpty ? null : row.doseId,
  completedOn: row.completedOn,
  skipped: row.skipped,
  note: row.note,
);
