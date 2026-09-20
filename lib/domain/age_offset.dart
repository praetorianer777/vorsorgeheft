/// A span of time measured from a date of birth.
///
/// Calendar units are applied before fixed ones, and month and year arithmetic
/// clamps to the last day of the target month: a child born on 31 May reaches
/// "one month" on 30 June, not on 1 July.
class AgeOffset {
  const AgeOffset({
    this.years = 0,
    this.months = 0,
    this.weeks = 0,
    this.days = 0,
    this.hours = 0,
  });

  factory AgeOffset.fromJson(Map<String, Object?> json) {
    int read(String key) {
      final value = json[key];
      if (value == null) return 0;
      if (value is int) return value;
      throw FormatException('"$key" must be a whole number, got $value');
    }

    const known = {'years', 'months', 'weeks', 'days', 'hours'};
    final unknown = json.keys.toSet().difference(known);
    if (unknown.isNotEmpty) {
      throw FormatException('unknown age unit(s): ${unknown.join(', ')}');
    }

    return AgeOffset(
      years: read('years'),
      months: read('months'),
      weeks: read('weeks'),
      days: read('days'),
      hours: read('hours'),
    );
  }

  final int years;
  final int months;
  final int weeks;
  final int days;
  final int hours;

  bool get isZero =>
      years == 0 && months == 0 && weeks == 0 && days == 0 && hours == 0;

  DateTime applyTo(DateTime birth) {
    final totalMonths = years * 12 + months;
    final shifted = _addMonths(birth, totalMonths);
    return shifted.add(Duration(days: weeks * 7 + days, hours: hours));
  }

  static DateTime _addMonths(DateTime from, int months) {
    if (months == 0) return from;
    final zeroBased = from.month - 1 + months;
    final year = from.year + (zeroBased / 12).floor();
    final month = zeroBased % 12 + 1;
    final day = from.day <= _daysInMonth(year, month)
        ? from.day
        : _daysInMonth(year, month);
    // Rebuilding the date must not quietly turn a UTC instant into a local one:
    // that shifts every derived due date by the timezone offset.
    final build = from.isUtc ? DateTime.utc : DateTime.new;
    return build(
      year,
      month,
      day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
      from.microsecond,
    );
  }

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  @override
  bool operator ==(Object other) =>
      other is AgeOffset &&
      other.years == years &&
      other.months == months &&
      other.weeks == weeks &&
      other.days == days &&
      other.hours == hours;

  @override
  int get hashCode => Object.hash(years, months, weeks, days, hours);

  @override
  String toString() {
    final parts = <String>[
      if (years != 0) '${years}y',
      if (months != 0) '${months}mo',
      if (weeks != 0) '${weeks}w',
      if (days != 0) '${days}d',
      if (hours != 0) '${hours}h',
    ];
    return parts.isEmpty ? 'AgeOffset(0)' : 'AgeOffset(${parts.join(' ')})';
  }
}
