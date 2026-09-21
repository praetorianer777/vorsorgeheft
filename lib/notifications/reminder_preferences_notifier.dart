import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'reminder_preferences.dart';

/// The reminder preferences of this phone, read once from the device-local
/// settings and written back on every change.
///
/// Starts on the defaults rather than unknown: the reminder service plans on
/// the very first frame, and planning on the defaults until the stored
/// choice arrives is the same plan the person had before they chose.
class ReminderPreferencesNotifier extends Notifier<ReminderPreferences> {
  @override
  ReminderPreferences build() {
    final database = ref.read(databaseProvider);
    Future(() async {
      final String? stored;
      try {
        stored = await database.settingValue(ReminderPreferences.settingKey);
      } on Object {
        // Same as the language: a database that closed under a notifier
        // that is already gone has nobody left to tell.
        if (!ref.mounted) return;
        rethrow;
      }
      if (!ref.mounted || stored == null) return;
      state = ReminderPreferences.decode(stored);
    });
    return const ReminderPreferences();
  }

  Future<void> update(ReminderPreferences preferences) async {
    state = preferences;
    await ref
        .read(databaseProvider)
        .putSetting(ReminderPreferences.settingKey, preferences.encode());
  }
}

final reminderPreferencesProvider =
    NotifierProvider<ReminderPreferencesNotifier, ReminderPreferences>(
      ReminderPreferencesNotifier.new,
    );
