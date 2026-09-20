import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/app/app.dart';
import 'package:vorsorgereminder/app/providers.dart';
import 'package:vorsorgereminder/data/catalog_repository.dart';
import 'package:vorsorgereminder/data/database.dart';
import 'package:vorsorgereminder/data/database_provider.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/l10n/locale_notifier.dart';

import '../fixtures/family.dart';

/// How the specs reach the catalogs.
///
/// Null means the real asset bundle, which is what a device run wants. The
/// headless run sets a synchronous bundle instead: it runs on a fake clock,
/// and a real asset read completes on the real event loop, which pumping
/// frames never advances.
AssetBundle? specAssetBundle;

/// Reads a catalog straight off disk, completing before it is awaited.
///
/// Deliberately not a CachingAssetBundle: a cached Future is created inside one
/// test's fake-async zone and awaited inside the next one's, where it never
/// completes. Reading the file again per test costs nothing and avoids that.
class SynchronousAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();
}

/// Boots the real app against a throwaway database and a fixed clock.
///
/// A run must not touch the database the person using the device actually has,
/// and it must start from a known state or an expectation about what is due
/// depends on what an earlier run left behind. Both fall out of using an
/// in-memory database seeded per test.
Future<AppDatabase> launchApp(
  WidgetTester tester, {
  List<Person> people = const [],
  DateTime? today,
  Locale locale = const Locale('en'),
}) async {
  final database = openInMemoryDatabase();
  for (final person in people) {
    await database.upsertPerson(person);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        if (specAssetBundle != null)
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository(bundle: specAssetBundle),
          ),
        clockProvider.overrideWithValue(() => today ?? pinnedToday),
        localeProvider.overrideWith(() => _FixedLocale(locale)),
      ],
      child: const VorsorgereminderApp(),
    ),
  );
  await settle(tester);
  return database;
}

/// Shuts the app down while the test body is still running.
///
/// The binding checks for pending timers before registered teardowns run, and
/// drift schedules one when its stream queries are cancelled, so leaving this
/// to `addTearDown` ends every test on "a Timer is still pending".
Future<void> shutDown(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await database.close();
  await tester.pump(const Duration(seconds: 1));
}

/// pumpAndSettle waits for every animation to end, and a progress indicator
/// never ends, so the first frame of any screen would hang it.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// A list only builds what is on screen, so anything further down has to be
/// scrolled to before it can be found.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(Scrollable).last,
    const Offset(0, -220),
  );
  await settle(tester);
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this._locale);

  final Locale _locale;

  @override
  Locale build() => _locale;
}
