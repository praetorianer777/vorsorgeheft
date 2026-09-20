import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../export/schedule_export.dart';
import '../l10n/app_localizations.dart';

/// Exports the schedule and offers the file for sharing.
///
/// The wording is assembled here rather than inside the exporter, which knows
/// nothing about Flutter: everything that ends up in the file is localised the
/// same way the screen it was triggered from is.
class ExportButton extends ConsumerWidget {
  const ExportButton({this.personId, this.personName, super.key});

  /// Null exports the whole family.
  final String? personId;
  final String? personName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const Key('export-ics'),
      icon: const Icon(Icons.ios_share_outlined),
      tooltip: l10n.exportCalendar,
      onPressed: () => _export(context, ref, l10n),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final locale = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final name = personName == null
        ? l10n.exportCalendarFamily
        : l10n.exportCalendarPerson(personName!);

    try {
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
}
