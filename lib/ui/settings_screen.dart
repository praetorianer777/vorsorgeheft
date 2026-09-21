import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/version.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_notifier.dart';
import '../support/problem_report.dart';
import '../support/support_prompt.dart';
import '../notifications/reminder_preferences.dart';
import '../notifications/reminder_preferences_notifier.dart';
import 'export_action.dart';
import 'how_it_works_screen.dart';
import 'sources_screen.dart';
import 'sync_screen.dart';

/// What belongs to this device rather than to the family.
///
/// The language override is stored in the Settings table and deliberately kept
/// out of the sync oplog: which language a phone is read in is a property of
/// the phone, and replicating it would change the language on the other
/// parent's device.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(localeProvider)?.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l10n.languageLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          RadioGroup<String?>(
            groupValue: selected,
            onChanged: (value) => ref
                .read(localeProvider.notifier)
                .set(value == null ? null : Locale(value)),
            child: Column(
              children: [
                RadioListTile<String?>(
                  key: const Key('language-system'),
                  value: null,
                  title: Text(l10n.languageSystem),
                ),
                RadioListTile<String?>(
                  key: const Key('language-de'),
                  value: 'de',
                  title: Text(l10n.languageGerman),
                ),
                RadioListTile<String?>(
                  key: const Key('language-en'),
                  value: 'en',
                  title: Text(l10n.languageEnglish),
                ),
              ],
            ),
          ),
          const Divider(),
          const _ReminderSection(),
          const Divider(),
          const ExportTile(),
          ListTile(
            key: const Key('settings-open-sync'),
            leading: const Icon(Icons.sync),
            title: Text(l10n.syncTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen())),
          ),
          ListTile(
            key: const Key('open-how-it-works'),
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.howTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HowItWorksScreen()),
            ),
          ),
          ListTile(
            key: const Key('open-sources'),
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.sourcesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SourcesScreen()),
            ),
          ),
          ListTile(
            key: const Key('support-link'),
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.supportLink),
            subtitle: Text(l10n.supportLinkHint),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(
              Uri.parse(supportUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            key: const Key('report-problem'),
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.reportProblem),
            subtitle: Text(l10n.reportProblemHint),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(
              problemReportUrl(
                appVersion: appVersion,
                os: Platform.operatingSystem,
                osVersion: Platform.operatingSystemVersion,
                locale: Localizations.localeOf(context).languageCode,
              ),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tag_outlined),
            title: Text(l10n.appVersion(appVersion)),
          ),
        ],
      ),
    );
  }
}

/// When and how often this phone reminds. Nothing here reaches the other
/// phone; see [ReminderPreferences].
class _ReminderSection extends ConsumerWidget {
  const _ReminderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(reminderPreferencesProvider);
    final notifier = ref.read(reminderPreferencesProvider.notifier);
    final time = TimeOfDay(hour: prefs.hour, minute: prefs.minute);

    Future<void> pickTime() async {
      final picked = await showTimePicker(context: context, initialTime: time);
      if (picked == null) return;
      await notifier.update(
        prefs.copyWith(hour: picked.hour, minute: picked.minute),
      );
    }

    Widget leadChips({
      required String keyPrefix,
      required List<int> chosen,
      required void Function(List<int>) onChanged,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          for (final days in ReminderPreferences.leadChoices)
            FilterChip(
              key: Key('$keyPrefix-$days'),
              label: Text(l10n.reminderLeadDays(days)),
              selected: chosen.contains(days),
              onSelected: !prefs.enabled
                  ? null
                  : (selected) => onChanged(
                      selected
                          ? [...chosen, days]
                          : chosen.where((d) => d != days).toList(),
                    ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            l10n.notificationsTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SwitchListTile(
          key: const Key('reminders-enabled'),
          title: Text(l10n.remindersEnabled),
          subtitle: Text(l10n.remindersEnabledHint),
          value: prefs.enabled,
          onChanged: (value) => notifier.update(prefs.copyWith(enabled: value)),
        ),
        ListTile(
          key: const Key('reminders-time'),
          enabled: prefs.enabled,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(l10n.remindersTime),
          subtitle: Text(time.format(context)),
          onTap: prefs.enabled ? pickTime : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(l10n.remindersBeforeWindow),
        ),
        leadChips(
          keyPrefix: 'reminder-lead',
          chosen: prefs.beforeWindowOpens,
          onChanged: (days) =>
              notifier.update(prefs.copyWith(beforeWindowOpens: days)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(l10n.remindersBeforeDeadline),
        ),
        leadChips(
          keyPrefix: 'deadline-lead',
          chosen: prefs.beforeDeadline,
          onChanged: (days) =>
              notifier.update(prefs.copyWith(beforeDeadline: days)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
