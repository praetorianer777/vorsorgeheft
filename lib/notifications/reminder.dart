import 'dart:convert';

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
    this.doseId,
  });

  /// Stable across restarts, so rescheduling replaces a notification rather
  /// than adding a second copy of it. Derived from what the reminder is about,
  /// never from a counter or from Dart's own hashCode, which is not promised
  /// to stay the same between releases.
  final int id;

  final String occurrenceKey;
  final String personId;
  final String ruleId;

  /// The dose of a vaccination series, so acting on the notification records
  /// the dose it was about rather than the rule as a whole.
  final String? doseId;

  final ReminderKind kind;

  /// Local time, because a reminder belongs to a time of day where the person
  /// is, not to an instant.
  final DateTime fireAt;

  /// How far ahead of the thing it warns about this fires.
  final Duration leadTime;

  @override
  String toString() => 'PlannedReminder($occurrenceKey, ${kind.name}, $fireAt)';
}

/// What a notification carries, so that acting on it does not mean guessing
/// which appointment it was about.
///
/// A bare occurrence key would have to be taken apart again to find the
/// person, and a person id may contain the separator.
class ReminderPayload {
  const ReminderPayload({
    required this.occurrenceKey,
    required this.personId,
    required this.ruleId,
    this.doseId,
  });

  factory ReminderPayload.of(PlannedReminder reminder) => ReminderPayload(
    occurrenceKey: reminder.occurrenceKey,
    personId: reminder.personId,
    ruleId: reminder.ruleId,
    doseId: reminder.doseId,
  );

  /// Null when the payload is not one of ours, which is what an old
  /// notification from a previous version looks like.
  static ReminderPayload? tryParse(String? raw) {
    if (raw == null) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final key = json['key'];
    final person = json['person'];
    final rule = json['rule'];
    if (key is! String || person is! String || rule is! String) return null;
    final dose = json['dose'];
    return ReminderPayload(
      occurrenceKey: key,
      personId: person,
      ruleId: rule,
      doseId: dose is String ? dose : null,
    );
  }

  final String occurrenceKey;
  final String personId;
  final String ruleId;
  final String? doseId;

  String encode() => jsonEncode({
    'key': occurrenceKey,
    'person': personId,
    'rule': ruleId,
    if (doseId != null) 'dose': doseId,
  });
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
  Map<String, DateTime> putOff = const {},
}) {
  final planned = <PlannedReminder>[];

  for (final occurrence in occurrences) {
    if (!occurrence.isOpen) continue;

    // Put off from the notification: the one reminder the person asked for
    // takes the place of every lead this appointment would otherwise get,
    // until the day they named.
    final until = putOff[occurrence.key];
    if (until != null && until.isAfter(now)) {
      _add(
        planned,
        occurrence: occurrence,
        kind: ReminderKind.windowOpens,
        target: until,
        lead: Duration.zero,
        settings: settings,
        now: now,
      );
      continue;
    }

    final before = planned.length;
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
    // A window that opens sooner than the shortest lead would otherwise get
    // no warning at all: the newborn screening, 36 hours after birth, on a
    // baby entered on the day it was born. One reminder at the next
    // configured time of day stands in for the leads that are already past.
    if (planned.length == before &&
        settings.beforeWindowOpens.isNotEmpty &&
        occurrence.status == OccurrenceStatus.upcoming) {
      _add(
        planned,
        occurrence: occurrence,
        kind: ReminderKind.windowOpens,
        target: _nextTimeOfDay(now, settings),
        lead: Duration.zero,
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

/// Today at the configured time if that is still ahead, else tomorrow.
DateTime _nextTimeOfDay(DateTime now, ReminderSettings settings) {
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    settings.hour,
    settings.minute,
  );
  return today.isAfter(now) ? today : today.add(const Duration(days: 1));
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
      doseId: occurrence.doseId,
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
