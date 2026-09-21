import 'dart:convert';

import 'reminder.dart';

/// What the person chose about reminders on this phone, stored as one
/// device-local setting.
///
/// Device-local like the language: what one parent's phone rings at is not a
/// fact about the family, and replicating it would silence or wake the other
/// phone. Everything not chosen keeps the [ReminderSettings] default, so an
/// installed app that never saw this screen keeps behaving as before.
class ReminderPreferences {
  const ReminderPreferences({
    this.enabled = true,
    this.hour = 9,
    this.minute = 0,
    this.beforeWindowOpens = const [30, 14, 3],
    this.beforeDeadline = const [30, 7],
  });

  factory ReminderPreferences.decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const ReminderPreferences();
    final Object? json;
    try {
      json = jsonDecode(encoded);
    } on FormatException {
      return const ReminderPreferences();
    }
    if (json is! Map) return const ReminderPreferences();
    List<int> days(Object? value, List<int> fallback) => value is List
        ? [
            for (final v in value)
              if (v is int) v,
          ]
        : fallback;
    const defaults = ReminderPreferences();
    return ReminderPreferences(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      hour: json['hour'] is int ? json['hour'] as int : defaults.hour,
      minute: json['minute'] is int ? json['minute'] as int : defaults.minute,
      beforeWindowOpens: days(
        json['beforeWindowOpens'],
        defaults.beforeWindowOpens,
      ),
      beforeDeadline: days(json['beforeDeadline'], defaults.beforeDeadline),
    );
  }

  static const settingKey = 'reminders.preferences';

  /// The lead times a person can pick from, in days. Offered as a fixed set
  /// rather than a free number: "remind me 30, 14 and 3 days ahead" is a
  /// choice, "remind me 11 days ahead" is a text field nobody wanted.
  static const leadChoices = [30, 14, 7, 3, 1];

  final bool enabled;
  final int hour;
  final int minute;

  /// Days before a window opens, in the order the reminders fire.
  final List<int> beforeWindowOpens;

  /// Days before an exclusion deadline.
  final List<int> beforeDeadline;

  ReminderPreferences copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    List<int>? beforeWindowOpens,
    List<int>? beforeDeadline,
  }) => ReminderPreferences(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    beforeWindowOpens: beforeWindowOpens ?? this.beforeWindowOpens,
    beforeDeadline: beforeDeadline ?? this.beforeDeadline,
  );

  /// The planner's settings: none at all when reminders are off, which
  /// leaves the plan empty and cancels whatever is pending.
  ReminderSettings toSettings() => ReminderSettings(
    beforeWindowOpens: enabled
        ? [for (final d in _sorted(beforeWindowOpens)) Duration(days: d)]
        : const [],
    beforeDeadline: enabled
        ? [for (final d in _sorted(beforeDeadline)) Duration(days: d)]
        : const [],
    hour: hour,
    minute: minute,
  );

  String encode() => jsonEncode({
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'beforeWindowOpens': beforeWindowOpens,
    'beforeDeadline': beforeDeadline,
  });

  static List<int> _sorted(List<int> days) =>
      days.toSet().toList()..sort((a, b) => b.compareTo(a));
}
