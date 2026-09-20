import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/export/ics.dart';

void main() {
  IcsEvent event({
    String summary = 'U6',
    String description = 'A check-up',
    List<IcsAlarm> alarms = const [],
  }) => IcsEvent(
    uid: 'infant-u6@vorsorgereminder',
    sequence: 0,
    summary: summary,
    description: description,
    start: DateTime.utc(2027, 6, 1),
    endExclusive: DateTime.utc(2027, 9, 1),
    alarms: alarms,
  );

  String render(IcsEvent e) => writeCalendar(
    events: [e],
    stamp: DateTime.utc(2026, 9, 20, 12),
    name: 'Preventive care',
    description: 'Not medical advice',
  );

  test('every line ends in CRLF, as the format requires', () {
    final ics = render(event());
    expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
    expect(ics.split('\r\n').length, greaterThan(5));
    expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
  });

  test('an all-day date carries no time and no zone', () {
    final ics = render(event());
    expect(ics, contains('DTSTART;VALUE=DATE:20270601'));
    // DTEND is exclusive: the window's last day is the 31st of August.
    expect(ics, contains('DTEND;VALUE=DATE:20270901'));
    expect(ics, isNot(contains('DTSTART;VALUE=DATE:20270601T')));
  });

  test('a comma, a semicolon and a newline are escaped, not dropped', () {
    final ics = render(event(description: 'One, two; three\\four\nfive'));
    expect(ics, contains('DESCRIPTION:One\\, two\\; three\\\\four\\nfive'));
  });

  test('a long line is folded at 75 octets', () {
    final ics = render(event(description: 'x' * 200));
    final lines = ics.split('\r\n');
    for (final line in lines) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
    expect(lines.where((l) => l.startsWith(' ')), isNotEmpty);
  });

  test('folding never splits a multi-byte character', () {
    final ics = render(event(description: 'ä' * 80));
    // Decoding back is the actual assertion: a fold inside a UTF-8 sequence
    // produces a different string, not an error.
    final unfolded = ics.replaceAll('\r\n ', '');
    expect(unfolded, contains('DESCRIPTION:${'ä' * 80}'));
  });

  test('a lead time becomes a negative ISO-8601 duration', () {
    final ics = render(
      event(
        alarms: [
          const IcsAlarm.beforeStart(Duration(days: 30), description: 'U6'),
          IcsAlarm.at(
            DateTime.utc(2027, 8, 2, 8),
            description: 'U6 is about to lapse',
          ),
        ],
      ),
    );
    expect(ics, contains('TRIGGER:-P30D'));
    expect(ics, contains('TRIGGER;VALUE=DATE-TIME:20270802T080000Z'));
  });

  test('a cancelled event still carries its uid, so an import supersedes', () {
    final ics = writeCalendar(
      events: [
        IcsEvent(
          uid: 'infant-u6@vorsorgereminder',
          sequence: 3,
          summary: 'U6',
          description: 'Recorded',
          start: DateTime.utc(2027, 6, 1),
          endExclusive: DateTime.utc(2027, 6, 2),
          cancelled: true,
        ),
      ],
      stamp: DateTime.utc(2026, 9, 20, 12),
      name: 'Preventive care',
      description: 'Not medical advice',
    );
    expect(ics, contains('UID:infant-u6@vorsorgereminder'));
    expect(ics, contains('STATUS:CANCELLED'));
    expect(ics, contains('SEQUENCE:3'));
  });
}
