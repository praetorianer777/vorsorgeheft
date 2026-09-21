import '../l10n/app_localizations.dart';

/// How far away a date is, in the coarsest unit that still says something.
///
/// A window that opens in three weeks is worth reading as "in 3 weeks" rather
/// than as 21 days, and the unit has to change with the distance or a date ten
/// years out reads as a four-digit number of days. The thresholds below are
/// where one unit stops being informative and the next takes over.
String formatRelativeDate(
  AppLocalizations l10n,
  DateTime date,
  DateTime today,
) {
  final days = _dateOnly(date).difference(_dateOnly(today)).inDays;
  if (days == 0) return l10n.relativeToday;

  final distance = days.abs();
  final ahead = days > 0;

  if (distance < 14) {
    return ahead
        ? l10n.relativeInDays(distance)
        : l10n.relativeDaysAgo(distance);
  }
  if (distance < 60) {
    final weeks = (distance / 7).round();
    return ahead ? l10n.relativeInWeeks(weeks) : l10n.relativeWeeksAgo(weeks);
  }
  if (distance < 365) {
    final months = (distance / 30).round();
    return ahead
        ? l10n.relativeInMonths(months)
        : l10n.relativeMonthsAgo(months);
  }
  final years = (distance / 365).round();
  return ahead ? l10n.relativeInYears(years) : l10n.relativeYearsAgo(years);
}

DateTime _dateOnly(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
