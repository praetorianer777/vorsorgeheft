import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/database.dart';

const localeSettingKey = 'locale';

/// The language override, if the user picked one. Null means follow the system.
///
/// Device-local on purpose: it is a preference of this phone, not a fact about
/// the family, so it is not replicated by the sync in #10.
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    final database = ref.read(databaseProvider);
    Future(() => _restore(database));
    return null;
  }

  /// The read is not awaited by anyone, so by the time it lands the notifier
  /// may already have been disposed with its container; touching the ref then
  /// throws into whatever the event loop is running at that moment. Hence the
  /// database is taken before the gap and the ref is checked after it.
  Future<void> _restore(AppDatabase database) async {
    final String? stored;
    try {
      stored = await database.settingValue(localeSettingKey);
    } on Object {
      // A database that closed under a notifier that is already gone is the
      // one failure with nobody left to tell.
      if (!ref.mounted) return;
      rethrow;
    }
    if (!ref.mounted) return;
    if (stored != null && stored.isNotEmpty) state = Locale(stored);
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    await ref
        .read(databaseProvider)
        .putSetting(localeSettingKey, locale?.languageCode ?? '');
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
