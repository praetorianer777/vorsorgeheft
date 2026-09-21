import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';
import 'package:vorsorgeheft/notifications/reminder_preferences.dart';

void main() {
  test('the defaults are the planner defaults', () {
    final settings = const ReminderPreferences().toSettings();
    const planner = ReminderSettings();
    expect(settings.beforeWindowOpens, planner.beforeWindowOpens);
    expect(settings.beforeDeadline, planner.beforeDeadline);
    expect(settings.hour, planner.hour);
    expect(settings.minute, planner.minute);
  });

  test('a choice round-trips through the stored form', () {
    const chosen = ReminderPreferences(
      enabled: true,
      hour: 7,
      minute: 30,
      beforeWindowOpens: [7, 1],
      beforeDeadline: [14],
    );
    final back = ReminderPreferences.decode(chosen.encode());
    expect(back.hour, 7);
    expect(back.minute, 30);
    expect(back.beforeWindowOpens, [7, 1]);
    expect(back.beforeDeadline, [14]);
    expect(back.enabled, isTrue);
  });

  test('switched off means nothing is planned', () {
    final settings = const ReminderPreferences(enabled: false).toSettings();
    expect(settings.beforeWindowOpens, isEmpty);
    expect(settings.beforeDeadline, isEmpty);
  });

  test('lead times are planned longest first, without duplicates', () {
    final settings = const ReminderPreferences(
      beforeWindowOpens: [3, 30, 3, 14],
    ).toSettings();
    expect(settings.beforeWindowOpens.map((d) => d.inDays), [30, 14, 3]);
  });

  test('a stored value from an older version falls back field by field', () {
    final back = ReminderPreferences.decode('{"hour": 20, "junk": true}');
    expect(back.hour, 20);
    expect(back.minute, 0);
    expect(back.beforeWindowOpens, [30, 14, 3]);
    expect(ReminderPreferences.decode('not json at all').hour, 9);
    expect(ReminderPreferences.decode(null).enabled, isTrue);
  });
}
