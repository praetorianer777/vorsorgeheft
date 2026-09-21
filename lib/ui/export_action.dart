import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../export/schedule_export.dart';
import '../l10n/app_localizations.dart';
import '../sync/replicated_store.dart';

/// Exports the schedule and offers the file for sharing.
///
/// The wording is assembled here rather than inside the exporter, which knows
/// nothing about Flutter: everything that ends up in the file is localised the
/// same way the screen it was triggered from is.
/// Exports the schedule and offers the file for sharing.
///
/// The wording is assembled here rather than inside the exporter, which knows
/// nothing about Flutter: everything that ends up in the file is localised the
/// same way the screen it was triggered from is.
Future<void> exportSchedule(
  BuildContext context,
  WidgetRef ref, {
  String? personId,
  String? personName,
}) async {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  final messenger = ScaffoldMessenger.of(context);

  try {
    final familyName = await ref
        .read(databaseProvider)
        .familyName(ReplicatedStore.familyId);
    final name = personName != null
        ? l10n.exportCalendarPerson(personName)
        : familyName ?? l10n.exportCalendarFamily;
    final service = ref.read(icsExportServiceProvider);
    final file = await service.export(
      personId: personId,
      locale: locale,
      texts: IcsTexts(
        calendarName: name,
        disclaimer: l10n.disclaimerBody,
        source: l10n.sourceLabel,
        notStatutory: l10n.notStatutory,
        deadline: l10n.exportDeadlineLine,
      ),
    );
    await service.shareExport(file, subject: name);
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
  }
}

/// The share icon on one person's timeline.
class ExportButton extends ConsumerWidget {
  const ExportButton({
    required this.personId,
    required this.personName,
    super.key,
  });

  final String personId;
  final String personName;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: const Key('export-person-ics'),
    icon: const Icon(Icons.ios_share_outlined),
    tooltip: AppLocalizations.of(context).exportCalendar,
    onPressed: () => exportSchedule(
      context,
      ref,
      personId: personId,
      personName: personName,
    ),
  );
}

/// The whole family's export, where it can be found with a label next to it.
class ExportTile extends ConsumerWidget {
  const ExportTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const Key('export-ics'),
      leading: const Icon(Icons.ios_share_outlined),
      title: Text(l10n.exportCalendar),
      subtitle: Text(l10n.exportCalendarFamily),
      onTap: () => exportSchedule(context, ref),
    );
  }
}
