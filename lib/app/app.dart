import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/locale_notifier.dart';
import '../notifications/reminder_sync.dart';
import '../ui/family_screen.dart';
import '../ui/sync_listener.dart';

class VorsorgeheftApp extends ConsumerWidget {
  const VorsorgeheftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    locale: ref.watch(localeProvider),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D6F)),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF2E7D6F),
      brightness: Brightness.dark,
    ),
    home: const ReminderSync(child: SyncListener(child: FamilyScreen())),
  );
}
