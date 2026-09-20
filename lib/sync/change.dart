import 'dart:convert';

import 'hlc.dart';

/// One field of one record, as of one moment.
///
/// Replication works at field level rather than record level: if one parent
/// renames a child while the other records an appointment, both edits survive.
/// Sending whole records would make the later write erase the earlier one.
class Change {
  const Change({
    required this.entity,
    required this.entityId,
    required this.field,
    required this.hlc,
    required this.value,
  });

  factory Change.fromJson(Map<String, Object?> json) {
    for (final key in ['entity', 'id', 'field', 'hlc']) {
      if (json[key] is! String) {
        throw FormatException('change is missing "$key"');
      }
    }
    return Change(
      entity: json['entity']! as String,
      entityId: json['id']! as String,
      field: json['field']! as String,
      hlc: Hlc.parse(json['hlc']! as String),
      value: json['value'],
    );
  }

  /// The field a deletion is recorded in.
  ///
  /// A delete is an ordinary change rather than a removal, because a row that
  /// is simply gone cannot beat a concurrent edit arriving from the other
  /// device - it would come back on the next sync.
  static const deletedField = '__deleted';

  final String entity;
  final String entityId;
  final String field;
  final Hlc hlc;

  /// JSON-encodable: a string, number, bool or null.
  final Object? value;

  String get key => '$entity/$entityId/$field';
  bool get isDeletion => field == deletedField && value == true;

  /// Whether this change replaces [existing].
  ///
  /// The whole conflict resolution is this one line. Equal timestamps mean the
  /// same change seen twice, which must leave the state untouched, so the
  /// comparison is strict.
  bool wins(Change? existing) => existing == null || hlc > existing.hlc;

  Map<String, Object?> toJson() => {
    'entity': entity,
    'id': entityId,
    'field': field,
    'hlc': hlc.toString(),
    'value': value,
  };

  String encodeValue() => jsonEncode(value);

  static Object? decodeValue(String encoded) => jsonDecode(encoded) as Object?;

  @override
  String toString() => 'Change($key, $hlc, $value)';
}

/// The merged state of a set of changes, kept in memory.
///
/// The database keeps the same state durably; this is the same rule with
/// nothing else attached, which is what makes the convergence properties
/// testable without a database.
class ChangeSet {
  ChangeSet([Iterable<Change> changes = const []]) {
    merge(changes);
  }

  final Map<String, Change> _winners = {};

  /// Applies [changes] and returns the ones that actually took effect.
  ///
  /// Merging is commutative, associative and idempotent: the same changes in
  /// any order, with any repeats, leave the same state. Two devices that have
  /// seen the same changes therefore agree without having to agree on an
  /// order in which to have seen them.
  List<Change> merge(Iterable<Change> changes) {
    final applied = <Change>[];
    for (final change in changes) {
      if (!change.wins(_winners[change.key])) continue;
      _winners[change.key] = change;
      applied.add(change);
    }
    return applied;
  }

  Iterable<Change> get all => _winners.values;

  Change? operator [](String key) => _winners[key];

  /// Everything newer than [watermark], which is what a peer that last synced
  /// at that point has not seen.
  List<Change> since(Hlc watermark) =>
      _winners.values.where((c) => c.hlc > watermark).toList()
        ..sort((a, b) => a.hlc.compareTo(b.hlc));

  Hlc? get latest => _winners.values.isEmpty
      ? null
      : _winners.values.map((c) => c.hlc).reduce((a, b) => a > b ? a : b);

  /// The live fields of one record, or null if it is deleted or absent.
  ///
  /// A deletion only counts while nothing newer has been written to the
  /// record, so an edit that happened after a delete brings the record back
  /// rather than being silently dropped.
  Map<String, Object?>? record(String entity, String entityId) {
    final prefix = '$entity/$entityId/';
    final fields = <String, Object?>{};
    Hlc? deletedAt;
    Hlc? newestField;

    for (final change in _winners.values) {
      if (!change.key.startsWith(prefix)) continue;
      if (change.field == Change.deletedField) {
        if (change.value == true) deletedAt = change.hlc;
        continue;
      }
      fields[change.field] = change.value;
      if (newestField == null || change.hlc > newestField) {
        newestField = change.hlc;
      }
    }

    if (fields.isEmpty) return null;
    if (deletedAt != null && (newestField == null || deletedAt > newestField)) {
      return null;
    }
    return fields;
  }
}
