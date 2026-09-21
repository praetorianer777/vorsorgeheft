import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/app/providers.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/l10n/locale_notifier.dart';

/// The override is restored asynchronously, because reading it is a database
/// query. A fresh container therefore starts on the system language and
/// switches once the stored value arrives.
Future<Locale?> restored(ProviderContainer container) async {
  for (var i = 0; i < 100; i++) {
    final locale = container.read(localeProvider);
    if (locale != null) return locale;
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(localeProvider);
}

void main() {
  late AppDatabase database;

  setUp(() => database = openInMemoryDatabase());
  tearDown(() => database.close());

  ProviderContainer restart() {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'a chosen language is stored and comes back on the next launch',
    () async {
      final first = restart();
      expect(first.read(localeProvider), isNull);
      await first.read(localeProvider.notifier).set(const Locale('de'));

      expect(await database.settingValue(localeSettingKey), 'de');
      expect(await restored(restart()), const Locale('de'));
    },
  );

  test('going back to the system language clears the override', () async {
    final first = restart();
    await first.read(localeProvider.notifier).set(const Locale('de'));
    await first.read(localeProvider.notifier).set(null);

    expect(await database.settingValue(localeSettingKey), isEmpty);
    expect(await restored(restart()), isNull);
  });

  test('the override is not replicated to the other device', () async {
    final container = restart();
    await container.read(localeProvider.notifier).set(const Locale('en'));

    expect(await database.changesFor('setting', localeSettingKey), isEmpty);
  });

  test('a restore that lands after the container is gone is dropped', () async {
    await database.putSetting(localeSettingKey, 'de');
    final container = restart();
    container.read(localeProvider);
    container.dispose();
    // The read started in build is still in flight; let it complete.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
}
