import '../domain/occurrence.dart';
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

/// The distance that is worth acting on for one appointment, or null when
/// there is none.
///
/// The date an entitlement *opened* is what the timeline used to show, and for
/// a screening that opened twenty years ago that number helps nobody. What a
/// parent needs is how long until the window opens, how long is left to use
/// it, or how long it has been missed - and nothing at all for an entitlement
/// that stays open indefinitely.
String? formatTimelineDistance(
  AppLocalizations l10n,
  Occurrence occurrence,
  DateTime today,
) {
  switch (occurrence.status) {
    case OccurrenceStatus.upcoming:
      return formatRelativeDate(l10n, occurrence.windowStart, today);
    case OccurrenceStatus.due:
      final end = occurrence.windowEnd;
      return end == null ? null : formatRemaining(l10n, end, today);
    case OccurrenceStatus.overdue:
      final deadline = occurrence.deadline;
      if (deadline != null) return formatRemaining(l10n, deadline, today);
      final end = occurrence.windowEnd;
      return end == null ? null : formatRelativeDate(l10n, end, today);
    case OccurrenceStatus.expired:
    case OccurrenceStatus.done:
    case OccurrenceStatus.skipped:
      return null;
  }
}

/// "3 weeks left" until [until], in the same coarse units as the relative
/// dates.
String formatRemaining(AppLocalizations l10n, DateTime until, DateTime today) {
  final days = _dateOnly(until).difference(_dateOnly(today)).inDays;
  if (days <= 0) return l10n.remainingToday;
  if (days < 14) return l10n.remainingDays(days);
  if (days < 60) return l10n.remainingWeeks((days / 7).round());
  if (days < 365) return l10n.remainingMonths((days / 30).round());
  return l10n.remainingYears((days / 365).round());
}
