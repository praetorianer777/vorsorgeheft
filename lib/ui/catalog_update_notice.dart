import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/catalog.dart';
import '../l10n/app_localizations.dart';

/// Device-local, like the sync notices: which catalog editions this phone has
/// already shown are a fact about this phone, not about the family.
const catalogsSeenSettingKey = 'catalogs.seen';

/// The catalogs whose edition differs from the one this phone last showed.
///
/// Empty on a first launch, which records the shipped editions silently: there
/// is nothing to compare against, and a banner about "changes" on a fresh
/// install would announce nothing. After that the list stays until dismissed,
/// across restarts, so an update is not missed because the app was closed
/// before the family screen was looked at.
class CatalogUpdates extends AsyncNotifier<List<Catalog>> {
  @override
  Future<List<Catalog>> build() async {
    final catalogs = await ref.watch(catalogsProvider.future);
    final db = ref.read(databaseProvider);
    final stored = await db.settingValue(catalogsSeenSettingKey);
    if (stored == null || stored.isEmpty) {
      await db.putSetting(catalogsSeenSettingKey, _encode(catalogs));
      return const [];
    }
    final seen = (jsonDecode(stored) as Map).cast<String, Object?>();
    return [
      for (final catalog in catalogs.catalogs)
        if (seen[catalog.id] != catalog.version) catalog,
    ];
  }

  Future<void> dismiss() async {
    final catalogs = await ref.read(catalogsProvider.future);
    state = const AsyncValue.data([]);
    await ref
        .read(databaseProvider)
        .putSetting(catalogsSeenSettingKey, _encode(catalogs));
  }

  static String _encode(CatalogSet catalogs) =>
      jsonEncode({for (final c in catalogs.catalogs) c.id: c.version});
}

final catalogUpdatesProvider =
    AsyncNotifierProvider<CatalogUpdates, List<Catalog>>(CatalogUpdates.new);

/// Tells the family, once per catalog edition, that an app update changed the
/// guidelines behind their appointments, and what changed.
class CatalogUpdateBanner extends ConsumerWidget {
  const CatalogUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(catalogUpdatesProvider).value ?? const [];
    if (updates.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;

    return MaterialBanner(
      key: const Key('catalog-update'),
      leading: const Icon(Icons.new_releases_outlined),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.catalogUpdateTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final catalog in updates) Text(_line(l10n, catalog, locale)),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('catalog-update-dismiss'),
          onPressed: () => ref.read(catalogUpdatesProvider.notifier).dismiss(),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

String _line(AppLocalizations l10n, Catalog catalog, String locale) {
  final note = catalog.latestChange?.note(locale);
  if (note == null) return '${catalog.name(locale)} ${catalog.version}';
  return l10n.catalogUpdateLine(catalog.name(locale), catalog.version, note);
}
