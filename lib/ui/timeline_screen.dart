import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/occurrence.dart';
import '../l10n/app_localizations.dart';
import 'export_action.dart';
import 'formatting.dart';
import 'occurrence_detail_screen.dart';
import 'person_form_screen.dart';

/// The four groups a timeline is split into.
///
/// What costs something if ignored comes first; what is already settled sinks
/// to the bottom, and what can no longer be had is last but still visible,
/// because a lapsed entitlement is something a parent should be able to find.
enum TimelineSection { needsAttention, comingUp, settled, expired }

TimelineSection sectionOf(OccurrenceStatus status) => switch (status) {
  OccurrenceStatus.due ||
  OccurrenceStatus.overdue => TimelineSection.needsAttention,
  OccurrenceStatus.upcoming => TimelineSection.comingUp,
  OccurrenceStatus.done || OccurrenceStatus.skipped => TimelineSection.settled,
  OccurrenceStatus.expired => TimelineSection.expired,
};

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
        data: (occurrences) => _Timeline(occurrences: occurrences),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.occurrences});

  final List<Occurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = <TimelineSection, List<Occurrence>>{};
    for (final occurrence in occurrences) {
      grouped
          .putIfAbsent(sectionOf(occurrence.status), () => [])
          .add(occurrence);
    }

    final children = <Widget>[];
    for (final section in TimelineSection.values) {
      final items = grouped[section];
      if (items == null || items.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(switch (section) {
            TimelineSection.needsAttention => l10n.sectionNeedsAttention,
            TimelineSection.comingUp => l10n.sectionComingUp,
            TimelineSection.settled => l10n.sectionSettled,
            TimelineSection.expired => l10n.sectionExpired,
          }, style: Theme.of(context).textTheme.titleSmall),
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

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;
    final labels = <String>[
      statusLabel(l10n, occurrence.status),
      if (!occurrence.rule.statutory) l10n.notStatutory,
      if (occurrence.applicability == Applicability.possible) l10n.mayApply,
    ];

    return ListTile(
      key: Key('occurrence-${occurrence.key}'),
      title: Text(occurrence.rule.title(locale)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            occurrence.completedOn != null
                ? l10n.completedOnLabel(occurrence.completedOn!)
                : formatRange(
                    context,
                    occurrence.windowStart,
                    occurrence.windowEnd,
                  ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final label in labels)
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: label == labels.first
                        ? statusColor(scheme, occurrence.status)
                        : scheme.onSurfaceVariant,
                  ),
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
