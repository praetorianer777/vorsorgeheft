import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/person.dart';
import '../l10n/app_localizations.dart';
import '../notifications/permission_state.dart';
import '../support/support_prompt.dart';
import '../support/support_prompt_notifier.dart';
import 'formatting.dart';
import 'person_form_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'timeline_screen.dart';

class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final persons = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.familyTitle),
        actions: [
          IconButton(
            key: const Key('open-sync'),
            icon: const Icon(Icons.sync),
            tooltip: l10n.syncTitle,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen())),
          ),
          IconButton(
            key: const Key('open-settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-person'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PersonFormScreen()),
        ),
        icon: const Icon(Icons.person_add_outlined),
        label: Text(l10n.addPerson),
      ),
      body: Column(
        children: [
          if (ref.watch(notificationPermissionProvider) == false)
            MaterialBanner(
              key: const Key('notifications-denied'),
              content: Text(l10n.notificationsDenied),
              leading: const Icon(Icons.notifications_off_outlined),
              actions: [
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: Text(l10n.notificationsEnable),
                ),
              ],
            ),
          if (ref.watch(supportPromptDueProvider))
            MaterialBanner(
              key: const Key('support-prompt'),
              content: Text(l10n.supportPromptBody(supportPromptThreshold)),
              leading: const Icon(Icons.favorite_outline),
              actions: [
                TextButton(
                  key: const Key('support-prompt-dismiss'),
                  onPressed: () => ref
                      .read(supportPromptDismissedProvider.notifier)
                      .dismiss(),
                  child: Text(l10n.supportPromptDismiss),
                ),
                FilledButton.tonal(
                  key: const Key('support-prompt-open'),
                  onPressed: () {
                    ref.read(supportPromptDismissedProvider.notifier).dismiss();
                    launchUrl(
                      Uri.parse(supportUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Text(l10n.supportPromptOpen),
                ),
              ],
            ),
          Expanded(
            child: _Family(persons: persons, l10n: l10n),
          ),
        ],
      ),
    );
  }
}

class _Family extends StatelessWidget {
  const _Family({required this.persons, required this.l10n});

  final AsyncValue<List<Person>> persons;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => persons.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Center(child: Text('$error')),
    data: (people) => people.isEmpty
        ? _Empty(l10n: l10n)
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: people.length,
            itemBuilder: (context, i) => _PersonTile(person: people[i]),
          ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.familyEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.familyEmptyBody,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final attention = ref.watch(familyAttentionProvider(person.id));
    final today = ref.watch(clockProvider)();

    return ListTile(
      key: Key('person-${person.id}'),
      leading: CircleAvatar(
        child: Text(person.name.characters.firstOrNull?.toUpperCase() ?? '?'),
      ),
      title: Text(person.name),
      subtitle: Text(formatAge(l10n, person.dateOfBirth, today)),
      trailing: attention == 0
          ? const Icon(Icons.chevron_right)
          : Badge(
              label: Text('$attention'),
              child: const Icon(Icons.chevron_right),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(personId: person.id),
        ),
      ),
    );
  }
}
