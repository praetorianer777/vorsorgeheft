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
  final AgeOffset to;

  /// The last age at which the appointment can still be caught up. For the
  /// children's check-ups this is an exclusion deadline, not a suggestion: once
  /// it passes the statutory entitlement is gone.
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

/// A booster that falls due a fixed interval after the last dose of another
/// rule, such as the tetanus and diphtheria refresher every ten years.
final class Booster extends Schedule {
  const Booster({required this.every, this.after, this.fromAge});

  factory Booster.fromJson(Map<String, Object?> json) {
    final after = json['after'];
    if (after != null && after is! String) {
      throw const FormatException('"schedule.after" must be a rule id');
    }
    return Booster(
      every: Schedule._offset(json, 'every'),
      after: after as String?,
      fromAge: Schedule._optionalOffset(json, 'fromAge'),
    );
  }

  final AgeOffset every;

  /// The rule whose last completion the interval counts from. Null means this
  /// rule's own last completion.
  final String? after;

  /// The earliest age the booster can fall due, for someone with nothing
  /// recorded yet.
  final AgeOffset? fromAge;
}
