import 'dart:convert';

import '../domain/occurrence.dart';
import '../domain/person.dart';
import '../notifications/reminder.dart';
import 'ics.dart';

/// The wording the exported file carries, already localised.
///
/// Passed in rather than looked up, so that building a calendar stays a pure
/// function of the schedule and can be compared against a golden file.
class IcsTexts {
  const IcsTexts({
    required this.calendarName,
    required this.disclaimer,
    required this.source,
    required this.notStatutory,
    required this.deadline,
  });

  final String calendarName;
  final String disclaimer;
  final String Function(String name, DateTime asOf) source;
  final String notStatutory;
  final String Function(DateTime date) deadline;
}

/// What a previous export wrote for one event, so the next one can tell an
/// unchanged appointment from a changed one.
class IcsExportRecord {
  const IcsExportRecord({required this.fingerprint, required this.sequence});

  final String fingerprint;
  final int sequence;
}

class IcsExport {
  const IcsExport({required this.content, required this.records});

  final String content;

  /// The bookkeeping to store for the next export. It keeps the uids of
  /// appointments that are no longer exported, because their cancellation may
  /// still have to be written once.
  final Map<String, IcsExportRecord> records;
}

/// Builds the calendar for one person or for the whole family.
///
/// Open appointments are always exported. A recorded or lapsed one is only
/// exported when a previous export already put it in someone's calendar, as a
/// cancellation - an import can add and update, so an event that is simply
/// left out stays behind forever.
IcsExport buildIcsExport({
  required List<Person> people,
  required List<Occurrence> occurrences,
  required String locale,
  required DateTime stamp,
  required IcsTexts texts,
  Map<String, IcsExportRecord> previous = const {},
  ReminderSettings reminders = const ReminderSettings(),
}) {
  final names = {for (final person in people) person.id: person.name};
  final events = <IcsEvent>[];
  final records = Map<String, IcsExportRecord>.from(previous);

  final sorted = [...occurrences]
    ..sort((a, b) {
      final byDate = a.windowStart.compareTo(b.windowStart);
      return byDate != 0 ? byDate : a.key.compareTo(b.key);
    });

  for (final occurrence in sorted) {
    final uid = '${occurrence.key}@vorsorgereminder';
    final cancelled = !occurrence.isOpen;
    if (cancelled && !previous.containsKey(uid)) continue;

    final event = _event(
      occurrence,
      uid: uid,
      personName: names[occurrence.personId] ?? '',
      locale: locale,
      texts: texts,
      reminders: reminders,
      cancelled: cancelled,
    );

    final fingerprint = _fingerprint(event);
    final before = previous[uid];
    final sequence = before == null
        ? 0
        : (before.fingerprint == fingerprint
              ? before.sequence
              : before.sequence + 1);

    events.add(event.withSequence(sequence));
    records[uid] = IcsExportRecord(
      fingerprint: fingerprint,
      sequence: sequence,
    );
  }

  return IcsExport(
    content: writeCalendar(
      events: events,
      stamp: stamp,
      name: texts.calendarName,
      description: texts.disclaimer,
    ),
    records: Map.unmodifiable(records),
  );
}

IcsEvent _event(
  Occurrence occurrence, {
  required String uid,
  required String personName,
  required String locale,
  required IcsTexts texts,
  required ReminderSettings reminders,
  required bool cancelled,
}) {
  final rule = occurrence.rule;
  final deadline = occurrence.deadline;
  final description = [
    rule.description(locale),
    if (!rule.statutory) texts.notStatutory,
    if (deadline != null) texts.deadline(deadline),
    texts.source(rule.source.name(locale), rule.source.asOf),
    rule.source.url,
  ].join('\n');

  final summary = personName.isEmpty
      ? rule.title(locale)
      : '$personName: ${rule.title(locale)}';

  final end = occurrence.windowEnd ?? occurrence.windowStart;

  return IcsEvent(
    uid: uid,
    sequence: 0,
    summary: summary,
    description: description,
    start: _dateOnly(occurrence.windowStart),
    endExclusive: _dateOnly(end).add(const Duration(days: 1)),
    categories: [rule.catalogId],
    url: rule.source.url,
    cancelled: cancelled,
    alarms: cancelled
        ? const []
        : [
            for (final lead in reminders.beforeWindowOpens)
              IcsAlarm.beforeStart(lead, description: summary),
            if (deadline != null)
              for (final lead in reminders.beforeDeadline)
                IcsAlarm.at(
                  _alarmInstant(_dateOnly(deadline).subtract(lead)),
                  description: texts.deadline(deadline),
                ),
          ],
  );
}

DateTime _dateOnly(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Absolute triggers are written at 08:00 UTC rather than at a local morning
/// hour: the exported file must not depend on which timezone the phone doing
/// the export happens to be in, or the same schedule would produce a different
/// calendar abroad.
DateTime _alarmInstant(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day, 8);

/// A content hash over everything a calendar would see, so that an export of
/// unchanged data keeps its sequence and a moved window raises it.
String _fingerprint(IcsEvent event) {
  final parts = [
    event.summary,
    event.description,
    formatDate(event.start),
    formatDate(event.endExclusive),
    event.categories.join(','),
    event.url ?? '',
    event.cancelled.toString(),
    for (final alarm in event.alarms)
      alarm.at != null ? formatInstant(alarm.at!) : '${alarm.lead!.inDays}d',
  ];

  var hash = 0xCBF29CE484222325;
  for (final byte in utf8.encode(parts.join('\u0000'))) {
    hash ^= byte;
    hash = (hash * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
