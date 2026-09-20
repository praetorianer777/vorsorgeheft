import 'rule.dart';
import 'schedule.dart';

/// Where an appointment stands relative to today.
enum OccurrenceStatus {
  /// Its window has not opened yet.
  upcoming,

  /// Today falls inside its window.
  due,

  /// Its window has closed but it can still be caught up.
  overdue,

  /// Its tolerance limit has passed and the entitlement is gone.
  expired,

  /// It was recorded as done.
  done,

  /// The family recorded a deliberate decision not to have it.
  skipped,
}

/// Whether the rule definitely applies to this person, or only might.
///
/// [possible] covers sex-specific screenings for someone whose sex is not
/// stated: showing them as due would be wrong, and hiding them would silently
/// drop an entitlement.
enum Applicability { definite, possible }

/// One appointment for one person, derived rather than stored.
class Occurrence {
  const Occurrence({
    required this.personId,
    required this.rule,
    required this.windowStart,
    required this.status,
    this.instanceId,
    this.windowEnd,
    this.deadline,
    this.completedOn,
    this.applicability = Applicability.definite,
    this.provisional = false,
  });

  final String personId;
  final Rule rule;

  /// Tells repeats of the same rule apart: the dose id for a vaccination
  /// series, the due date for something that recurs. Null when a rule yields a
  /// single appointment.
  final String? instanceId;

  final DateTime windowStart;

  /// The last day the appointment is still on time. Null for an entitlement
  /// that stays open once it opens, such as the hepatitis screening from 35.
  final DateTime? windowEnd;

  /// The date after which the entitlement lapses, for rules that have one.
  final DateTime? deadline;

  final OccurrenceStatus status;
  final DateTime? completedOn;
  final Applicability applicability;

  /// True when the window still depends on something unrecorded, such as a
  /// series dose whose predecessor has not been entered yet.
  final bool provisional;

  /// The dose a completion for this occurrence records.
  ///
  /// Only a vaccination series has doses. For a recurring entitlement the
  /// instance id is a date, which must never be stored as a dose id, or every
  /// repeat would be recorded as a separate appointment that no later
  /// recomputation can find again.
  String? get doseId => rule.schedule is Series ? instanceId : null;

  /// Stable across recomputation, and the basis of the ICS UID, so re-importing
  /// an export updates an event instead of duplicating it.
  String get key => instanceId == null
      ? '$personId-${rule.id}'
      : '$personId-${rule.id}#$instanceId';

  bool get isOpen =>
      status == OccurrenceStatus.upcoming ||
      status == OccurrenceStatus.due ||
      status == OccurrenceStatus.overdue;

  @override
  String toString() =>
      'Occurrence($key, ${status.name}, ${windowStart.toIso8601String()})';
}
