import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/providers.dart';
import '../domain/occurrence.dart';
import '../l10n/app_localizations.dart';
import '../notifications/reminder_preferences_notifier.dart';
import 'formatting.dart';
import 'sources_screen.dart';
import 'timeline_screen.dart';

const repositoryUrl = 'https://github.com/praetorianer777/vorsorgereminder';

/// The app explained to someone who has never heard of the G-BA.
///
/// The sources screen is the reference; this is the story. Where a section
/// makes a claim the code backs - the reminder offsets, the source documents,
/// the status glyphs - the values come from the same place the app reads
/// them, so the explanation cannot drift from the behaviour.
class HowItWorksScreen extends ConsumerWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final catalogs = ref.watch(catalogsProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final reminders = ref.watch(reminderPreferencesProvider).toSettings();

    String days(List<Duration> offsets) =>
        offsets.map((d) => d.inDays).join(', ');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.howTitle)),
      body: ListView(
        key: const Key('how-it-works'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Section(
            icon: Icons.menu_book_outlined,
            title: l10n.howOriginTitle,
            body: l10n.howOriginBody,
          ),
          if (catalogs != null)
            for (final catalog in catalogs.catalogs)
              for (final source in catalog.sources.values)
                ListTile(
                  key: Key('how-source-${source.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(source.name(locale)),
                  subtitle: Text(
                    '${source.url}\n${l10n.howSourceReviewed(source.asOf)}',
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(source.url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
          _Section(
            icon: Icons.calculate_outlined,
            title: l10n.howComputeTitle,
            body: l10n.howComputeBody,
          ),
          _Section(
            icon: Icons.legend_toggle_outlined,
            title: l10n.howStatusTitle,
          ),
          for (final (status, text) in [
            (OccurrenceStatus.upcoming, l10n.howStatusUpcoming),
            (OccurrenceStatus.due, l10n.howStatusDue),
            (OccurrenceStatus.overdue, l10n.howStatusOverdue),
            (OccurrenceStatus.expired, l10n.howStatusExpired),
            (OccurrenceStatus.done, l10n.howStatusDone),
            (OccurrenceStatus.skipped, l10n.howStatusSkipped),
          ])
            _Legend(
              icon: Icon(
                statusIcon(status),
                color: statusColor(scheme, status),
              ),
              label: statusLabel(l10n, status),
              text: text,
            ),
          _Legend(
            icon: const Icon(Icons.info_outline),
            label: l10n.notStatutory,
            text: l10n.howLabelNotStatutory,
          ),
          _Legend(
            icon: const Icon(Icons.help_outline),
            label: l10n.mayApply,
            text: l10n.howLabelMayApply,
          ),
          _Section(
            icon: Icons.notifications_outlined,
            title: l10n.howRemindersTitle,
            body: l10n.howRemindersBody(
              days(reminders.beforeWindowOpens),
              days(reminders.beforeDeadline),
            ),
          ),
          _Section(
            icon: Icons.lock_outline,
            title: l10n.howDataTitle,
            body: l10n.howDataBody,
          ),
          _Section(
            icon: Icons.update_outlined,
            title: l10n.howChangesTitle,
            body: l10n.howChangesBody,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('how-open-repository'),
            onPressed: () => launchUrl(
              Uri.parse(repositoryUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.code),
            label: Text(l10n.howOpenRepository),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('how-open-sources'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SourcesScreen()),
            ),
            icon: const Icon(Icons.info_outline),
            label: Text(l10n.howOpenSources),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (body != null) ...[const SizedBox(height: 8), Text(body!)],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.label, required this.text});

  final Widget icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
