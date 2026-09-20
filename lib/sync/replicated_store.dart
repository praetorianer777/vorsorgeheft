import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../domain/completion.dart';
import '../domain/person.dart';
import 'change.dart';
import 'hlc.dart';

/// Every write the app makes, recorded as replicated changes.
///
/// Nothing else in the app writes to the persons or completions tables: those
/// are a projection of the change log, rebuilt whenever a change lands. That
/// way a local edit and one arriving from the other parent's phone take
/// exactly the same path, and there is only one place where the two can
/// disagree.
class ReplicatedStore {
  ReplicatedStore(this._db, {required this.nodeId, DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  static const personEntity = 'person';
  static const completionEntity = 'completion';
  static const nodeIdSettingKey = 'node-id';

  final AppDatabase _db;
  final DateTime Function() _clock;
  final String nodeId;

  Hlc? _hlc;

  /// Restores the clock from what is already stored, so a restart cannot issue
  /// a timestamp that sorts before something this device has already written.
  static Future<ReplicatedStore> open(
    AppDatabase db, {
    DateTime Function()? clock,
    String? nodeId,
  }) async {
    var id = nodeId ?? await db.settingValue(nodeIdSettingKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await db.putSetting(nodeIdSettingKey, id);
    }
    final store = ReplicatedStore(db, nodeId: id, clock: clock);
    store._hlc = await db.latestHlc();
    return store;
  }

  Hlc _next() {
    final base = _hlc ?? Hlc.zero(nodeId);
    final issued = Hlc(
      millis: base.millis,
      counter: base.counter,
      nodeId: nodeId,
    ).issue(_clock());
    return _hlc = issued;
  }

  Future<void> savePerson(Person person) => _write(personEntity, person.id, {
    'name': person.name,
    'dateOfBirth': person.dateOfBirth.toIso8601String(),
    'sex': person.sex.name,
    'notes': person.notes,
  });

  Future<void> deletePerson(String id) =>
      _write(personEntity, id, {Change.deletedField: true});

  Future<void> recordCompletion(Completion completion) {
    final id = completionId(
      completion.personId,
      completion.ruleId,
      completion.doseId,
    );
    return _write(completionEntity, id, {
      'personId': completion.personId,
      'ruleId': completion.ruleId,
      'doseId': completion.doseId ?? '',
      'completedOn': completion.completedOn.toIso8601String(),
      'skipped': completion.skipped,
      'note': completion.note,
    });
  }

  Future<void> clearCompletion({
    required String personId,
    required String ruleId,
    String? doseId,
  }) => _write(completionEntity, completionId(personId, ruleId, doseId), {
    Change.deletedField: true,
  });

  static String completionId(String personId, String ruleId, String? doseId) =>
      '$personId|$ruleId|${doseId ?? ''}';

  /// Applies changes that came from a peer.
  ///
  /// The local clock moves past every timestamp seen, so anything written
  /// afterwards sorts after what the peer sent, even if this device's wall
  /// clock is behind theirs.
  Future<List<Change>> merge(Iterable<Change> incoming) async {
    final changes = incoming.toList();
    for (final change in changes) {
      _hlc = (_hlc ?? Hlc.zero(nodeId)).receive(change.hlc, _clock());
    }
    final applied = await _db.applyChanges(changes);
    await _project(applied);
    return applied;
  }

  Future<List<Change>> changesSince(Hlc watermark) =>
      _db.changesSince(watermark);

  Future<Hlc?> get latest => _db.latestHlc();

  Future<void> _write(
    String entity,
    String entityId,
    Map<String, Object?> fields,
  ) async {
    final changes = [
      for (final entry in fields.entries)
        Change(
          entity: entity,
          entityId: entityId,
          field: entry.key,
          hlc: _next(),
          value: entry.value,
        ),
    ];
    final applied = await _db.applyChanges(changes);
    await _project(applied);
  }

  /// Rebuilds the projected rows for every record a change touched.
  ///
  /// Rebuilding from the whole record rather than patching the one field that
  /// changed is what keeps the projection correct when a change arrives for a
  /// record this device has never seen, and when a deletion has to be undone
  /// by a newer edit.
  Future<void> _project(Iterable<Change> applied) async {
    final touched = <(String, String)>{
      for (final change in applied) (change.entity, change.entityId),
    };
    for (final (entity, entityId) in touched) {
      final fields = ChangeSet(
        await _db.changesFor(entity, entityId),
      ).record(entity, entityId);

      if (entity == personEntity) {
        if (fields == null) {
          await _db.deletePerson(entityId);
        } else {
          await _db.upsertPerson(_personFrom(entityId, fields));
        }
      } else if (entity == completionEntity) {
        if (fields == null) {
          await _deleteCompletion(entityId);
        } else {
          await _db.recordCompletion(_completionFrom(fields));
        }
      }
    }
  }

  Future<void> _deleteCompletion(String entityId) {
    final parts = entityId.split('|');
    return _db.clearCompletion(
      personId: parts[0],
      ruleId: parts[1],
      doseId: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  Person _personFrom(String id, Map<String, Object?> fields) => Person(
    id: id,
    name: fields['name'] as String? ?? '',
    dateOfBirth: DateTime.parse(fields['dateOfBirth']! as String),
    sex: Sex.values.firstWhere(
      (s) => s.name == fields['sex'],
      orElse: () => Sex.notStated,
    ),
    notes: fields['notes'] as String?,
  );

  Completion _completionFrom(Map<String, Object?> fields) => Completion(
    personId: fields['personId']! as String,
    ruleId: fields['ruleId']! as String,
    doseId: (fields['doseId'] as String?)?.isEmpty ?? true
        ? null
        : fields['doseId'] as String,
    completedOn: DateTime.parse(fields['completedOn']! as String),
    skipped: fields['skipped'] == true,
    note: fields['note'] as String?,
  );
}
