import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/completion.dart';
import '../domain/newborn_examinations.dart';
import '../domain/occurrence.dart';
import '../l10n/app_localizations.dart';

String clinicOfferDismissedKey(String personId) =>
    'clinic.offer.dismissed.$personId';

/// Whether the offer was declined for this child. Device-local like the
/// support prompt: what was recorded travels to the other phone, a "not now"
/// does not need to.
class ClinicOfferDismissed extends AsyncNotifier<bool> {
  ClinicOfferDismissed(this.personId);

  final String personId;

  @override
  Future<bool> build() async {
    final stored = await ref
        .read(databaseProvider)
        .settingValue(clinicOfferDismissedKey(personId));
    return stored == 'true';
  }

  Future<void> dismiss() async {
    state = const AsyncValue.data(true);
    await ref
        .read(databaseProvider)
        .putSetting(clinicOfferDismissedKey(personId), 'true');
  }
}

final clinicOfferDismissedProvider =
    AsyncNotifierProvider.family<ClinicOfferDismissed, bool, String>(
      ClinicOfferDismissed.new,
    );

/// The one-time card on a newborn's timeline offering to record the first
/// days' examinations in one go.
class ClinicOfferCard extends ConsumerWidget {
  const ClinicOfferCard({
    required this.personId,
    required this.personName,
    required this.timeline,
    super.key,
  });

  final String personId;
  final String personName;
  final List<Occurrence> timeline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(clinicOfferDismissedProvider(personId)).value;
    final pending = unrecordedNewbornExaminations(timeline);
    if (dismissed != false || pending.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    Future<void> recordAll() async {
      final store = ref.read(storeProvider);
      for (final occurrence in pending) {
        final day = occurrence.windowStart;
        await store.recordCompletion(
          Completion(
            personId: personId,
            ruleId: occurrence.rule.id,
            doseId: occurrence.doseId,
            completedOn: DateTime.utc(day.year, day.month, day.day),
          ),
        );
      }
      await ref.read(clinicOfferDismissedProvider(personId).notifier).dismiss();
    }

    return Card(
      key: const Key('clinic-offer'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.local_hospital_outlined,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.clinicOfferBody(personName))),
              ],
            ),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('clinic-offer-dismiss'),
                  onPressed: () => ref
                      .read(clinicOfferDismissedProvider(personId).notifier)
                      .dismiss(),
                  child: Text(l10n.clinicOfferDismiss),
                ),
                FilledButton(
                  key: const Key('clinic-offer-accept'),
                  onPressed: recordAll,
                  child: Text(l10n.clinicOfferAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
