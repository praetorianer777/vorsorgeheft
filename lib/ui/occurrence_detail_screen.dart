import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/providers.dart';
import '../domain/completion.dart';
import '../domain/occurrence.dart';
import '../l10n/app_localizations.dart';
import 'formatting.dart';

class OccurrenceDetailScreen extends ConsumerWidget {
  const OccurrenceDetailScreen({
    required this.personId,
    required this.occurrenceKey,
    super.key,
  });

  final String personId;
  final String occurrenceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final timeline = ref.watch(timelineProvider(personId)).value ?? const [];
    final occurrence = timeline
        .where((o) => o.key == occurrenceKey)
        .firstOrNull;

    if (occurrence == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }

    final rule = occurrence.rule;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(rule.title(locale))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            statusLabel(l10n, occurrence.status),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: statusColor(scheme, occurrence.status),
            ),
          ),
          const SizedBox(height: 12),
          Text(rule.description(locale)),
          const SizedBox(height: 24),
          _Field(
            label: l10n.windowLabel,
            value: formatRange(
              context,
              occurrence.windowStart,
              occurrence.windowEnd,
            ),
          ),
          if (occurrence.deadline != null)
            _Field(
              label: occurrence.status == OccurrenceStatus.expired
                  ? l10n.deadlinePassed(occurrence.deadline!)
                  : l10n.deadlineLabel,
              value: occurrence.status == OccurrenceStatus.expired
                  ? ''
                  : formatDate(context, occurrence.deadline!),
            ),
          if (occurrence.completedOn != null)
            _Field(
              label: l10n.completedOnLabel(occurrence.completedOn!),
              value: '',
            ),
          if (occurrence.provisional)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.provisional,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!rule.statutory)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.notStatutory,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          _Actions(occurrence: occurrence),
          const Divider(height: 48),
          Text(
            l10n.sourceLabel(rule.source.name(locale), rule.source.asOf),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (rule.source.document != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                rule.source.document!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(rule.source.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(l10n.openSource),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        if (value.isNotEmpty)
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(storeProvider);
    final settled =
        occurrence.status == OccurrenceStatus.done ||
        occurrence.status == OccurrenceStatus.skipped;

    if (settled) {
      return OutlinedButton.icon(
        key: const Key('undo-record'),
        onPressed: () => store.clearCompletion(
          personId: occurrence.personId,
          ruleId: occurrence.rule.id,
          doseId: occurrence.doseId,
        ),
        icon: const Icon(Icons.undo),
        label: Text(l10n.undoRecord),
      );
    }

    Future<void> record({required bool skipped}) async {
      final picked = skipped
          ? ref.read(clockProvider)()
          : await showDatePicker(
              context: context,
              initialDate: _initialDate(ref),
              firstDate: occurrence.windowStart.subtract(
                const Duration(days: 365 * 5),
              ),
              lastDate: ref.read(clockProvider)(),
            );
      if (picked == null) return;
      await store.recordCompletion(
        Completion(
          personId: occurrence.personId,
          ruleId: occurrence.rule.id,
          doseId: occurrence.doseId,
          completedOn: DateTime.utc(picked.year, picked.month, picked.day),
          skipped: skipped,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('mark-done'),
          onPressed: () => record(skipped: false),
          icon: const Icon(Icons.check),
          label: Text(l10n.markDone),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('mark-skipped'),
          onPressed: () => record(skipped: true),
          child: Text(l10n.markSkipped),
        ),
      ],
    );
  }

  DateTime _initialDate(WidgetRef ref) {
    final today = ref.read(clockProvider)();
    return occurrence.windowStart.isAfter(today)
        ? today
        : occurrence.windowStart;
  }
}
