import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

const localeSettingKey = 'locale';

/// The language override, if the user picked one. Null means follow the system.
///
/// Device-local on purpose: it is a preference of this phone, not a fact about
/// the family, so it is not replicated by the sync in #10.
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    Future(_restore);
    return null;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(databaseProvider)
        .settingValue(localeSettingKey);
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
