import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../domain/completion.dart';
import '../domain/person.dart';
import 'change.dart';
import 'hlc.dart';
import 'overwrite_notice.dart';

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
  static const familyEntity = 'family';

  /// There is one family per database, so its record has a fixed id.
  static const familyId = 'family';
  static const nodeIdSettingKey = 'node-id';

  /// Device-local, like the locale: the other phone must not be told about
  /// notices that are about what happened on this one.
  static const noticesSettingKey = 'sync.notices';

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

  /// A blank name clears it. The record stays rather than being deleted, so
  /// a name written later on either phone still wins by timestamp.
  Future<void> saveFamilyName(String name) =>
      _write(familyEntity, familyId, {'name': name.trim()});

  static String completionId(String personId, String ruleId, String? doseId) =>
      '$personId|$ruleId|${doseId ?? ''}';

  /// Applies changes that came from another device.
  ///
  /// The local clock moves past every timestamp seen, so anything written
  /// afterwards sorts after what the peer sent, even if this device's wall
  /// clock is behind theirs.
  ///
  /// [from] names the device the changes came from, for the notices about
  /// appointments this device had recorded differently.
  Future<MergeResult> merge(Iterable<Change> incoming, {String? from}) async {
    final changes = incoming.toList();
    for (final change in changes) {
      _hlc = (_hlc ?? Hlc.zero(nodeId)).receive(change.hlc, _clock());
    }
    final before = await _ownCompletions(changes);
    final applied = await _db.applyChanges(changes);
    await _project(applied);
    final overwritten = await _overwritten(before, applied, from);
    if (overwritten.isNotEmpty) await _remember(overwritten);
    return MergeResult(applied: applied, overwritten: overwritten);
  }

  /// The completions the incoming changes touch, as this device recorded
  /// them: only those whose winning date was written here count as "yours",
  /// because that is the entry the parent holding this phone remembers making.
  Future<Map<String, Map<String, Object?>>> _ownCompletions(
    List<Change> incoming,
  ) async {
    final ids = <String>{
      for (final c in incoming)
        if (c.entity == completionEntity) c.entityId,
    };
    final own = <String, Map<String, Object?>>{};
    for (final id in ids) {
      final changes = await _db.changesFor(completionEntity, id);
      final fields = ChangeSet(changes).record(completionEntity, id);
      if (fields == null) continue;
      final date = changes.firstWhereOrNull((c) => c.field == 'completedOn');
      if (date?.hlc.nodeId == nodeId) own[id] = fields;
    }
    return own;
  }

  Future<List<OverwriteNotice>> _overwritten(
    Map<String, Map<String, Object?>> before,
    List<Change> applied,
    String? from,
  ) async {
    final notices = <OverwriteNotice>[];
    final touched = <String>{
      for (final c in applied)
        if (c.entity == completionEntity && c.hlc.nodeId != nodeId) c.entityId,
    };
    for (final id in touched) {
      final previous = before[id];
      if (previous == null) continue;
      final current = ChangeSet(
        await _db.changesFor(completionEntity, id),
      ).record(completionEntity, id);
      final previousDate = previous['completedOn'] as String;
      final currentDate = current?['completedOn'] as String?;
      final previousSkipped = previous['skipped'] == true;
      final currentSkipped = current?['skipped'] == true;
      if (currentDate == previousDate && currentSkipped == previousSkipped) {
        continue;
      }
      final parts = id.split('|');
      notices.add(
        OverwriteNotice(
          personId: parts[0],
          ruleId: parts[1],
          doseId: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
          previousDate: DateTime.parse(previousDate),
          previousSkipped: previousSkipped,
          currentDate: currentDate == null ? null : DateTime.parse(currentDate),
          currentSkipped: currentSkipped,
          fromNodeId: from ?? '',
        ),
      );
    }
    return notices;
  }

  Future<void> _remember(List<OverwriteNotice> notices) async {
    final stored = OverwriteNotice.decodeList(
      await _db.settingValue(noticesSettingKey),
    );
    await _db.putSetting(
      noticesSettingKey,
      OverwriteNotice.encodeList([...stored, ...notices]),
    );
  }

  Stream<List<OverwriteNotice>> watchNotices() =>
      _db.watchSetting(noticesSettingKey).map(OverwriteNotice.decodeList);

  Future<void> clearNotices() => _db.putSetting(noticesSettingKey, '');

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
      } else if (entity == familyEntity) {
        final name = fields?['name'] as String? ?? '';
        if (name.isEmpty) {
          await _db.deleteFamily(entityId);
        } else {
          await _db.upsertFamily(entityId, name);
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

/// What a merge did: the changes that took effect, and the appointments this
/// device had recorded that now read differently because of them.
class MergeResult {
  const MergeResult({required this.applied, required this.overwritten});

  final List<Change> applied;
  final List<OverwriteNotice> overwritten;
}
