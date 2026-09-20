import 'dart:convert';

/// One alarm on an event.
///
/// A trigger is either relative to the start of its event or an absolute UTC
/// instant. The deadline warnings need the absolute form: they are anchored on
/// the date an entitlement lapses, which is not the event's start, and a
/// relative trigger can only refer to the event's own start or end.
class IcsAlarm {
  const IcsAlarm.beforeStart(this.lead, {required this.description})
    : at = null;

  const IcsAlarm.at(DateTime instant, {required this.description})
    : at = instant,
      lead = null;

  final Duration? lead;
  final DateTime? at;
  final String description;
}

/// One event in the exported calendar.
class IcsEvent {
  const IcsEvent({
    required this.uid,
    required this.sequence,
    required this.summary,
    required this.description,
    required this.start,
    required this.endExclusive,
    this.categories = const [],
    this.url,
    this.alarms = const [],
    this.cancelled = false,
  });

  /// Stable across exports of the same appointment, which is what lets a
  /// calendar update an event on re-import instead of adding a second copy.
  final String uid;

  /// Raised whenever anything below it changes. A calendar ignores an update
  /// whose sequence is not higher than the one it already holds.
  final int sequence;

  final String summary;
  final String description;

  /// The first day of the window, as a date without a time or a zone.
  final DateTime start;

  /// The day *after* the last day of the window. DTEND is exclusive for
  /// all-day events, so a one-day appointment ends on the following day.
  final DateTime endExclusive;

  final List<String> categories;
  final String? url;
  final List<IcsAlarm> alarms;

  /// Marks an appointment that was exported before and has since been recorded
  /// or has lapsed. Dropping it from the file would leave the old event in the
  /// calendar forever, because an import can only add and update.
  final bool cancelled;

  IcsEvent withSequence(int sequence) => IcsEvent(
    uid: uid,
    sequence: sequence,
    summary: summary,
    description: description,
    start: start,
    endExclusive: endExclusive,
    categories: categories,
    url: url,
    alarms: alarms,
    cancelled: cancelled,
  );
}

/// Serialises a calendar to RFC 5545.
String writeCalendar({
  required Iterable<IcsEvent> events,
  required DateTime stamp,
  required String name,
  required String description,
}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//vorsorgereminder//Vorsorgereminder//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_escape(name)}',
    'X-WR-CALDESC:${_escape(description)}',
  ];

  for (final event in events) {
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${_escape(event.uid)}',
      'DTSTAMP:${formatInstant(stamp)}',
      'SEQUENCE:${event.sequence}',
      'DTSTART;VALUE=DATE:${formatDate(event.start)}',
      'DTEND;VALUE=DATE:${formatDate(event.endExclusive)}',
      'SUMMARY:${_escape(event.summary)}',
      'DESCRIPTION:${_escape(event.description)}',
      if (event.categories.isNotEmpty)
        'CATEGORIES:${event.categories.map(_escape).join(',')}',
      if (event.url != null) 'URL:${_escape(event.url!)}',
      'STATUS:${event.cancelled ? 'CANCELLED' : 'CONFIRMED'}',
      // A preventive-care window is not time the person is busy; marking it
      // opaque would make weeks of a calendar look booked.
      'TRANSP:TRANSPARENT',
    ]);
    for (final alarm in event.alarms) {
      lines.addAll([
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_escape(alarm.description)}',
        if (alarm.at != null)
          'TRIGGER;VALUE=DATE-TIME:${formatInstant(alarm.at!)}'
        else
          'TRIGGER:${formatDuration(alarm.lead!)}',
        'END:VALARM',
      ]);
    }
    lines.add('END:VEVENT');
  }

  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}'
    '${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}';

String formatInstant(DateTime instant) {
  final utc = instant.toUtc();
  return '${formatDate(utc)}T'
      '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}Z';
}

/// A negative ISO-8601 duration, which is how a trigger says "this long
/// before". Whole days are emitted as days, because that is what the
/// reminder offsets are.
String formatDuration(Duration lead) {
  if (lead.inSeconds % Duration.secondsPerDay == 0) {
    return '-P${lead.inDays}D';
  }
  return '-PT${lead.inHours}H';
}

String _escape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n');

/// Folds a content line to 75 octets.
///
/// The limit counts bytes, not characters, and a fold must never land inside a
/// multi-byte character - which is why this walks the UTF-8 encoding rather
/// than the string.
String _fold(String line) {
  final bytes = utf8.encode(line);
  if (bytes.length <= 75) return line;

  final folded = StringBuffer();
  var start = 0;
  var limit = 75;
  while (start < bytes.length) {
    var end = start + limit;
    if (end >= bytes.length) {
      end = bytes.length;
    } else {
      while (end > start && (bytes[end] & 0xC0) == 0x80) {
        end--;
      }
    }
    if (folded.isNotEmpty) folded.write('\r\n ');
    folded.write(utf8.decode(bytes.sublist(start, end)));
    start = end;
    // A continuation line begins with the fold space, which counts towards
    // its own 75 octets.
    limit = 74;
  }
  return folded.toString();
}
