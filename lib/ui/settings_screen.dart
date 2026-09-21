import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/version.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_notifier.dart';
import 'sources_screen.dart';

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
            leading: const Icon(Icons.tag_outlined),
            title: Text(l10n.appVersion(appVersion)),
          ),
        ],
      ),
    );
  }
}
