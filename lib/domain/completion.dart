/// A record that an appointment happened, or that the family chose to skip it.
///
/// Completions are the only mutable state the schedule derives from; every due
/// date is recomputed rather than stored.
class Completion {
  const Completion({
    required this.personId,
    required this.ruleId,
    required this.completedOn,
    this.doseId,
    this.skipped = false,
    this.note,
  });

  final String personId;
  final String ruleId;

  /// Which dose of a vaccination series this records. Null for everything else.
  final String? doseId;

  final DateTime completedOn;
  final bool skipped;
  final String? note;

  String get occurrenceKey => doseId == null ? ruleId : '$ruleId#$doseId';

  @override
  String toString() =>
      'Completion($personId, $occurrenceKey, ${completedOn.toIso8601String()})';
}
