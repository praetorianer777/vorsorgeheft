import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Where every appointment in the app comes from, plus what this app is not.
///
/// This screen is the other half of the promise the catalogs make: each rule
/// names its source, and here they are all in one place with the date they
/// were last reviewed, so a stale catalog is visible rather than merely wrong.
class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final catalogs = ref.watch(catalogsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourcesTitle)),
      body: catalogs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (set) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.sourcesIntro),
            for (final catalog in set.catalogs) ...[
              const SizedBox(height: 24),
              Text(
                l10n.catalogVersionLabel(catalog.name(locale), catalog.version),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final source in catalog.sources.values)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sourceLabel(source.name(locale), source.asOf),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (source.document != null)
                        Text(
                          source.document!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(source.url),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l10n.openSource),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const Divider(height: 48),
            Text(
              l10n.disclaimerTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(l10n.disclaimerBody),
            const SizedBox(height: 24),
            Text(
              l10n.privacyTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(l10n.privacyBody),
          ],
        ),
      ),
    );
  }
}
