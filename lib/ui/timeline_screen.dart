import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/occurrence.dart';
import '../l10n/app_localizations.dart';
import 'clinic_offer.dart';
import 'export_action.dart';
import 'formatting.dart';
import 'occurrence_detail_screen.dart';
import 'person_form_screen.dart';
import 'relative_time.dart';

/// The five groups a timeline is split into, in the order they are shown.
///
/// What costs something if ignored comes first. What has lapsed follows what
/// is coming up rather than sinking to the bottom: for someone entered years
/// after their first appointments it is the longest part of the list, every
/// entry of it can still be recorded, and below a group that runs to the
/// colonoscopy at fifty nobody finds it. What is already settled comes after
/// it, and the distant future last, because nothing there asks anything of
/// anyone today. What opens more than [farAheadAfter] from today counts as
/// distant, so next year's check-up is not listed beside that colonoscopy.
enum TimelineSection { needsAttention, comingUp, expired, settled, farAhead }

/// The distance at which an upcoming appointment stops being "coming up".
const farAheadAfter = 5;

TimelineSection sectionOf(Occurrence occurrence, DateTime today) =>
    switch (occurrence.status) {
      OccurrenceStatus.due ||
      OccurrenceStatus.overdue => TimelineSection.needsAttention,
      OccurrenceStatus.upcoming =>
        occurrence.windowStart.isAfter(
              DateTime.utc(today.year + farAheadAfter, today.month, today.day),
            )
            ? TimelineSection.farAhead
            : TimelineSection.comingUp,
      OccurrenceStatus.done ||
      OccurrenceStatus.skipped => TimelineSection.settled,
      OccurrenceStatus.expired => TimelineSection.expired,
    };

/// Orders what needs attention by urgency rather than by when it opened:
/// overdue before due, and within each the entry that lapses first at the
/// top. An entitlement that never closes goes last, because there is no day
/// on which it becomes too late.
int compareUrgency(Occurrence a, Occurrence b) {
  final overdueFirst =
      (b.status == OccurrenceStatus.overdue ? 1 : 0) -
      (a.status == OccurrenceStatus.overdue ? 1 : 0);
  if (overdueFirst != 0) return overdueFirst;
  final endA = a.deadline ?? a.windowEnd;
  final endB = b.deadline ?? b.windowEnd;
  if (endA == null && endB == null) {
    return a.windowStart.compareTo(b.windowStart);
  }
  if (endA == null) return 1;
  if (endB == null) return -1;
  return endA.compareTo(endB);
}

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({required this.personId, super.key});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final person = ref.watch(personProvider(personId));
    final timeline = ref.watch(timelineProvider(personId));

    if (person == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          ExportButton(personId: person.id, personName: person.name),
          IconButton(
            key: const Key('edit-person'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.editPerson,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PersonFormScreen(existing: person),
              ),
            ),
          ),
        ],
      ),
      body: timeline.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (occurrences) => _Timeline(
          personId: person.id,
          personName: person.name,
          occurrences: occurrences,
          today: ref.watch(clockProvider)(),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.personId,
    required this.personName,
    required this.occurrences,
    required this.today,
  });

  final String personId;
  final String personName;
  final List<Occurrence> occurrences;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = <TimelineSection, List<Occurrence>>{};
    for (final occurrence in occurrences) {
      grouped
          .putIfAbsent(sectionOf(occurrence, today), () => [])
          .add(occurrence);
    }
    grouped[TimelineSection.needsAttention]?.sort(compareUrgency);

    final children = <Widget>[
      ClinicOfferCard(
        personId: personId,
        personName: personName,
        timeline: occurrences,
      ),
    ];
    for (final section in TimelineSection.values) {
      final items = grouped[section];
      if (items == null || items.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            switch (section) {
              TimelineSection.needsAttention => l10n.sectionNeedsAttention,
              TimelineSection.comingUp => l10n.sectionComingUp,
              TimelineSection.farAhead => l10n.sectionFarAhead,
              TimelineSection.settled => l10n.sectionSettled,
              TimelineSection.expired => l10n.sectionExpired,
            },
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
      children.addAll(items.map((o) => _OccurrenceTile(occurrence: o)));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}

/// A glyph per status, so the state of an entry reads while scrolling and
/// not only once the small coloured word underneath is in focus.
IconData statusIcon(OccurrenceStatus status) => switch (status) {
  OccurrenceStatus.overdue => Icons.error_outline,
  OccurrenceStatus.due => Icons.circle_outlined,
  OccurrenceStatus.upcoming => Icons.schedule_outlined,
  OccurrenceStatus.done => Icons.check_circle_outline,
  OccurrenceStatus.skipped => Icons.remove_circle_outline,
  OccurrenceStatus.expired => Icons.block_outlined,
};

class _OccurrenceTile extends ConsumerWidget {
  const _OccurrenceTile({required this.occurrence});

  final Occurrence occurrence;

  /// The day an entitlement without an end opened is not a date to act on,
  /// so it is worded as the start of something still available rather than
  /// shown bare, where it reads as an appointment twenty years missed.
  String _dates(BuildContext context, AppLocalizations l10n) {
    if (occurrence.completedOn != null) {
      return l10n.completedOnLabel(occurrence.completedOn!);
    }
    if (occurrence.windowEnd == null &&
        occurrence.status == OccurrenceStatus.due) {
      return l10n.openSince(occurrence.windowStart);
    }
    return formatRange(context, occurrence.windowStart, occurrence.windowEnd);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(clockProvider)();
    final locale = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;
    final color = statusColor(scheme, occurrence.status);
    final distance = formatTimelineDistance(l10n, occurrence, today);
    final secondary = <String>[
      ?distance,
      if (!occurrence.rule.statutory) l10n.notStatutory,
      if (occurrence.applicability == Applicability.possible) l10n.mayApply,
    ];
    final labelStyle = Theme.of(context).textTheme.labelMedium;

    return ListTile(
      key: Key('occurrence-${occurrence.key}'),
      leading: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Icon(statusIcon(occurrence.status), color: color),
      ),
      title: Text(occurrenceTitle(l10n, locale, occurrence)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dates(context, l10n)),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            children: [
              Text(
                statusLabel(l10n, occurrence.status),
                style: labelStyle?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final label in secondary)
                Text(
                  label,
                  style: labelStyle?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OccurrenceDetailScreen(
            personId: occurrence.personId,
            occurrenceKey: occurrence.key,
          ),
        ),
      ),
    );
  }
}
