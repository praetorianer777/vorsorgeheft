import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/occurrence.dart';
import '../l10n/app_localizations.dart';

String formatDate(BuildContext context, DateTime date) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);

/// The rule title, with the dose spelled out for a vaccination series.
String occurrenceTitle(
  AppLocalizations l10n,
  String locale,
  Occurrence occurrence,
) {
  final title = occurrence.rule.title(locale);
  final number = occurrence.doseNumber;
  final total = occurrence.doseCount;
  if (number == null || total == null || total < 2) return title;
  return l10n.doseOf(title, number, total);
}

String formatRange(BuildContext context, DateTime start, DateTime? end) {
  if (end == null || end == start) return formatDate(context, start);
  return '${formatDate(context, start)} – ${formatDate(context, end)}';
}

String statusLabel(AppLocalizations l10n, OccurrenceStatus status) =>
    switch (status) {
      OccurrenceStatus.due => l10n.statusDue,
      OccurrenceStatus.overdue => l10n.statusOverdue,
      OccurrenceStatus.expired => l10n.statusExpired,
      OccurrenceStatus.upcoming => l10n.statusUpcoming,
      OccurrenceStatus.done => l10n.statusDone,
      OccurrenceStatus.skipped => l10n.statusSkipped,
    };

/// Overdue and expired are the two states that cost someone something, so they
/// carry the error colour; nothing else competes with them for attention.
Color statusColor(ColorScheme scheme, OccurrenceStatus status) =>
    switch (status) {
      OccurrenceStatus.overdue || OccurrenceStatus.expired => scheme.error,
      OccurrenceStatus.due => scheme.primary,
      OccurrenceStatus.done => scheme.tertiary,
      OccurrenceStatus.upcoming ||
      OccurrenceStatus.skipped => scheme.onSurfaceVariant,
    };

String formatAge(AppLocalizations l10n, DateTime birth, DateTime today) {
  var years = today.year - birth.year;
  var months = today.month - birth.month;
  if (today.day < birth.day) months--;
  if (months < 0) {
    years--;
    months += 12;
  }
  if (years > 0) return l10n.ageYears(years);
  if (months > 0) return l10n.ageMonths(months);
  return l10n.ageDays(today.difference(birth).inDays);
}
