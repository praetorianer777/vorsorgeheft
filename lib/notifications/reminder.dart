import '../domain/occurrence.dart';

/// Why a reminder is being sent.
enum ReminderKind {
  /// The window in which the appointment should happen is about to open, or
  /// has just opened.
  windowOpens,

  /// The entitlement is about to lapse. These carry more urgency because
  /// missing them costs money, not just time.
  deadlineApproaching,
}

/// One notification the app intends to deliver.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.occurrenceKey,
    required this.personId,
    required this.ruleId,
    required this.kind,
    required this.fireAt,
    required this.leadTime,
  });

  /// Stable across restarts, so rescheduling replaces a notification rather
  /// than adding a second copy of it. Derived from what the reminder is about,
  /// never from a counter or from Dart's own hashCode, which is not promised
  /// to stay the same between releases.
  final int id;

  final String occurrenceKey;
  final String personId;
  final String ruleId;
  final ReminderKind kind;

  /// Local time, because a reminder belongs to a time of day where the person
  /// is, not to an instant.
  final DateTime fireAt;

  /// How far ahead of the thing it warns about this fires.
  final Duration leadTime;

  @override
  String toString() => 'PlannedReminder($occurrenceKey, ${kind.name}, $fireAt)';
}

/// When reminders fire, and how many may be pending at once.
class ReminderSettings {
  const ReminderSettings({
    this.beforeWindowOpens = const [
      Duration(days: 30),
      Duration(days: 14),
      Duration(days: 3),
    ],
    this.beforeDeadline = const [Duration(days: 30), Duration(days: 7)],
    this.hour = 9,
    this.minute = 0,
    this.maxPending = 20,
  });

  final List<Duration> beforeWindowOpens;

  /// Only for rules whose tolerance limit is an exclusion deadline. A warning
  /// that an entitlement is about to lapse is the one reminder worth
  /// repeating.
  final List<Duration> beforeDeadline;

  final int hour;
  final int minute;

  /// iOS keeps only the 64 notifications that fire soonest and silently drops
  /// the rest, so the app schedules a rolling window well inside that limit
  /// and tops it up rather than trying to schedule everything.
  final int maxPending;
}

/// Works out which notifications to have pending right now.
///
/// Pure: it takes the appointments, the settings and the current local time,
/// and returns a list. Nothing here talks to a platform, which is what makes
/// the two limits below testable at all.
List<PlannedReminder> planReminders({
  required List<Occurrence> occurrences,
  required DateTime now,
  ReminderSettings settings = const ReminderSettings(),
}) {
  final planned = <PlannedReminder>[];

  for (final occurrence in occurrences) {
    if (!occurrence.isOpen) continue;

    for (final lead in settings.beforeWindowOpens) {
      _add(
        planned,
        occurrence: occurrence,
        kind: ReminderKind.windowOpens,
        target: occurrence.windowStart,
        lead: lead,
        settings: settings,
        now: now,
      );
    }

    final deadline = occurrence.deadline;
    if (deadline == null) continue;
    for (final lead in settings.beforeDeadline) {
      _add(
        planned,
        occurrence: occurrence,
        kind: ReminderKind.deadlineApproaching,
        target: deadline,
        lead: lead,
        settings: settings,
        now: now,
      );
    }
  }

  planned.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return List.unmodifiable(planned.take(settings.maxPending));
}

void _add(
  List<PlannedReminder> into, {
  required Occurrence occurrence,
  required ReminderKind kind,
  required DateTime target,
  required Duration lead,
  required ReminderSettings settings,
  required DateTime now,
}) {
  final day = target.subtract(lead);
  // Built in local time on purpose: a reminder belongs to nine in the morning
  // where the person is, and DateTime handles the days that are 23 or 25 hours
  // long.
  final fireAt = DateTime(
    day.year,
    day.month,
    day.day,
    settings.hour,
    settings.minute,
  );
  if (!fireAt.isAfter(now)) return;

  into.add(
    PlannedReminder(
      id: reminderId(occurrence.key, kind, lead),
      occurrenceKey: occurrence.key,
      personId: occurrence.personId,
      ruleId: occurrence.rule.id,
      kind: kind,
      fireAt: fireAt,
      leadTime: lead,
    ),
  );
}

/// A deterministic 31-bit id, because Android notification ids are ints and
/// have to survive a restart unchanged.
int reminderId(String occurrenceKey, ReminderKind kind, Duration lead) {
  var hash = 0x811C9DC5;
  for (final code in '$occurrenceKey|${kind.name}|${lead.inDays}'.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}
