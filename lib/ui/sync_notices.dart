import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../sync/overwrite_notice.dart';
import 'formatting.dart';

final syncNoticesProvider = StreamProvider<List<OverwriteNotice>>(
  (ref) => ref.watch(storeProvider).watchNotices(),
);

/// Tells the parent holding this phone which of their recorded appointments
/// the other phone's entries replaced, until they have read it.
///
/// Shown on the family screen rather than on the sync screen: the phone that
/// was synced *into* never had the sync screen open, and a snack bar on a
/// screen nobody is looking at is no notice at all.
class SyncNoticesBanner extends ConsumerWidget {
  const SyncNoticesBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(syncNoticesProvider).value ?? const [];
    if (notices.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final persons = ref.watch(personsProvider).value ?? const [];
    final catalogs = ref.watch(catalogsProvider).value;
    final peers = ref.watch(peersProvider).value ?? const [];

    String entry(DateTime date, bool skipped) {
      final day = formatDate(context, date);
      return skipped ? l10n.syncNoticeSkipped(day) : day;
    }

    final lines = <String>[];
    for (final notice in notices) {
      final person = persons.where((p) => p.id == notice.personId).firstOrNull;
      if (person == null) continue;
      final title =
          catalogs?.ruleById(notice.ruleId)?.title(locale) ?? notice.ruleId;
      final peer = peers
          .where((p) => p.nodeId == notice.fromNodeId)
          .firstOrNull;
      final device =
          peer?.deviceName ??
          (notice.fromNodeId.isEmpty
              ? l10n.syncNoticeOtherPhone
              : l10n.syncNoticeImportedFile);
      final previous = entry(notice.previousDate, notice.previousSkipped);
      lines.add(
        notice.removed
            ? l10n.syncNoticeRemoved(title, person.name, previous, device)
            : l10n.syncNoticeReplaced(
                title,
                person.name,
                previous,
                entry(notice.currentDate!, notice.currentSkipped),
                device,
              ),
      );
    }

    return MaterialBanner(
      key: const Key('sync-notices'),
      leading: const Icon(Icons.sync_problem_outlined),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.syncNoticesTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final line in lines) Text(line),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('sync-notices-dismiss'),
          onPressed: () => ref.read(storeProvider).clearNotices(),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
