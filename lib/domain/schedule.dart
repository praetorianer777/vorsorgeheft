import 'age_offset.dart';

/// How a rule turns a date of birth into one or more due windows.
sealed class Schedule {
  const Schedule();

  factory Schedule.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String) {
      throw const FormatException('"schedule.type" is required');
    }
    return switch (type) {
      'ageWindow' => AgeWindow.fromJson(json),
      'recurring' => Recurring.fromJson(json),
      'onceFromAge' => OnceFromAge.fromJson(json),
      'series' => Series.fromJson(json),
      'seasonal' => Seasonal.fromJson(json),
      'booster' => Booster.fromJson(json),
      _ => throw FormatException('unknown schedule type "$type"'),
    };
  }

  static AgeOffset _offset(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! Map) {
      throw FormatException('"schedule.$key" is required');
    }
    try {
      return AgeOffset.fromJson(value.cast<String, Object?>());
    } on FormatException catch (e) {
      throw FormatException('"schedule.$key": ${e.message}');
    }
  }

  static AgeOffset? _optionalOffset(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    return _offset(json, key);
  }
}

/// A single window between two ages, as used by the children's check-ups and
/// the dental examinations.
final class AgeWindow extends Schedule {
  const AgeWindow({
    required this.from,
    required this.to,
    this.toleranceTo,
    this.hardDeadline = false,
  });

  factory AgeWindow.fromJson(Map<String, Object?> json) {
    final window = AgeWindow(
      from: Schedule._offset(json, 'from'),
      to: Schedule._offset(json, 'to'),
      toleranceTo: Schedule._optionalOffset(json, 'toleranceTo'),
      hardDeadline: json['hardDeadline'] == true,
    );
    if (window.hardDeadline && window.toleranceTo == null) {
      throw const FormatException(
        '"hardDeadline" needs a "toleranceTo" to expire at',
      );
    }
    return window;
  }

  final AgeOffset from;

  /// The end of the window the appointment is meant to happen in. Past it the
  /// appointment is late but can still be caught up, up to [toleranceTo].
  final AgeOffset to;

  /// The last age at which the appointment can still be caught up. For the
  /// children's check-ups this is an exclusion deadline, not a suggestion: once
  /// it passes the statutory entitlement is gone.
  ///
  /// Where a guideline also allows an *earlier* start than the recommended
  /// window, that is deliberately not modelled: the app's job is to get people
  /// into the recommended window, and the earlier option belongs in the rule
  /// text rather than in the reminder.
  final AgeOffset? toleranceTo;

  final bool hardDeadline;
}

/// An appointment that repeats for the rest of someone's life, such as the
/// general check-up every three years from 35.
final class Recurring extends Schedule {
  const Recurring({required this.from, required this.every, this.until});

  factory Recurring.fromJson(Map<String, Object?> json) => Recurring(
    from: Schedule._offset(json, 'from'),
    every: Schedule._offset(json, 'every'),
    until: Schedule._optionalOffset(json, 'until'),
  );

  final AgeOffset from;
  final AgeOffset every;
  final AgeOffset? until;
}

/// An appointment that repeats from a fixed first date rather than from an
/// age, which is what a person's own appointments do. Never read from a
/// catalog, so it has no JSON form.
final class RecurringFromDate extends Schedule {
  const RecurringFromDate({required this.first, required this.every});

  final DateTime first;
  final AgeOffset every;
}

/// A one-off entitlement that opens at a given age, such as the hepatitis B
/// and C screening from 35.
final class OnceFromAge extends Schedule {
  const OnceFromAge({required this.from, this.until});

  factory OnceFromAge.fromJson(Map<String, Object?> json) => OnceFromAge(
    from: Schedule._offset(json, 'from'),
    until: Schedule._optionalOffset(json, 'until'),
  );

  final AgeOffset from;
  final AgeOffset? until;
}

/// One dose of a vaccination series.
class Dose {
  const Dose({
    required this.id,
    required this.from,
    this.to,
    this.minIntervalFromPrevious,
  });

  factory Dose.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('every dose needs an "id"');
    }
    return Dose(
      id: id,
      from: Schedule._offset(json, 'from'),
      to: Schedule._optionalOffset(json, 'to'),
      minIntervalFromPrevious: Schedule._optionalOffset(
        json,
        'minIntervalFromPrevious',
      ),
    );
  }

  final String id;
  final AgeOffset from;
  final AgeOffset? to;

  /// The shortest gap allowed after the previous dose was actually given. Until
  /// that dose is recorded the window can only be derived from age, so the
  /// computed occurrence is provisional.
  final AgeOffset? minIntervalFromPrevious;
}

/// A vaccination given as an ordered series, where each dose's earliest date
/// depends on when the previous one was actually given.
final class Series extends Schedule {
  const Series({required this.doses});

  factory Series.fromJson(Map<String, Object?> json) {
    final doses = json['doses'];
    if (doses is! List || doses.isEmpty) {
      throw const FormatException('"schedule.doses" must be a non-empty list');
    }
    final parsed = [
      for (final dose in doses) Dose.fromJson((dose as Map).cast()),
    ];
    final ids = parsed.map((d) => d.id).toSet();
    if (ids.length != parsed.length) {
      throw const FormatException('dose ids must be unique within a series');
    }
    return Series(doses: List.unmodifiable(parsed));
  }

  final List<Dose> doses;
}

/// A day in the calendar with no year: where a season opens or closes.
class SeasonDay {
  const SeasonDay({required this.month, required this.day});

  /// A missing day means the first of the month at the start of a season and
  /// the last of it at the end, so a season can be written as two months.
  factory SeasonDay.fromJson(Map<String, Object?> json, {required bool end}) {
    final month = json['month'];
    if (month is! int || month < 1 || month > 12) {
      throw const FormatException('a season needs a "month" from 1 to 12');
    }
    final day = json['day'];
    if (day != null && (day is! int || day < 1 || day > 31)) {
      throw const FormatException('a season\'s "day" must be a day of a month');
    }
    return SeasonDay(
      month: month,
      day: (day as int?) ?? (end ? _lastDayOf(month) : 1),
    );
  }

  final int month;
  final int day;

  /// February is given 28 days: a season that ends with the month ends on the
  /// 28th in a leap year too, which is a day nobody notices and saves the
  /// month from depending on the year.
  static int _lastDayOf(int month) =>
      const [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];

  DateTime inYear(int year) => DateTime.utc(year, month, day);
}

/// An appointment that comes round once per season rather than once per year
/// from a birthday: the flu vaccination, which the STIKO wants in the autumn
/// and winter whatever month somebody was born in.
final class Seasonal extends Schedule {
  const Seasonal({
    required this.from,
    required this.opens,
    required this.closes,
    this.until,
  });

  factory Seasonal.fromJson(Map<String, Object?> json) {
    Map<String, Object?> part(String key) {
      final value = json[key];
      if (value is! Map) {
        throw FormatException('"schedule.$key" is required');
      }
      return value.cast<String, Object?>();
    }

    return Seasonal(
      from: Schedule._offset(json, 'from'),
      until: Schedule._optionalOffset(json, 'until'),
      opens: SeasonDay.fromJson(part('opens'), end: false),
      closes: SeasonDay.fromJson(part('closes'), end: true),
    );
  }

  /// The age from which the season applies to this person at all.
  final AgeOffset from;

  /// The age past which it no longer does.
  final AgeOffset? until;

  final SeasonDay opens;

  /// The last day of the season. A season whose end falls in an earlier month
  /// than its start runs over the turn of the year.
  final SeasonDay closes;

  bool get spansNewYear =>
      closes.month < opens.month ||
      (closes.month == opens.month && closes.day < opens.day);

  /// The day the season that opens in [year] closes.
  DateTime closesAfter(int year) =>
      closes.inYear(spansNewYear ? year + 1 : year);
}

/// A booster that falls due a fixed interval after the last dose of another
/// rule, such as the tetanus and diphtheria refresher every ten years.
final class Booster extends Schedule {
  const Booster({
    required this.every,
    this.after,
    this.fromAge,
    this.thenEvery,
    this.repeats,
  });

  factory Booster.fromJson(Map<String, Object?> json) {
    final after = json['after'];
    if (after != null && after is! String) {
      throw const FormatException('"schedule.after" must be a rule id');
    }
    final repeats = json['repeats'];
    if (repeats != null && (repeats is! int || repeats < 1)) {
      throw const FormatException(
        '"schedule.repeats" must be a positive whole number',
      );
    }
    return Booster(
      every: Schedule._offset(json, 'every'),
      after: after as String?,
      fromAge: Schedule._optionalOffset(json, 'fromAge'),
      thenEvery: Schedule._optionalOffset(json, 'thenEvery'),
      repeats: repeats as int?,
    );
  }

  /// The interval from the primary series to the first booster, and between
  /// boosters unless [thenEvery] says otherwise.
  final AgeOffset every;

  /// The rule whose last completion the interval counts from. Null means this
  /// rule's own last completion.
  final String? after;

  /// The earliest age the booster can fall due, for someone with nothing
  /// recorded yet.
  final AgeOffset? fromAge;

  /// The interval once a booster has been given, where that differs from the
  /// first one: the TBE vaccination is refreshed three years after the series
  /// and every five years after that.
  final AgeOffset? thenEvery;

  /// How often this booster is given at all, where the entitlement is
  /// finite: the oKFE-RL grants a second screening colonoscopy ten years
  /// after the first and no third. Null is the usual case, a refresher for
  /// the rest of someone's life.
  ///
  /// Only appointments actually carried out count against it. Skipping the
  /// offer is not the same as using the entitlement up, so a skipped booster
  /// comes round again.
  final int? repeats;
}
