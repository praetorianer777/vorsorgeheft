import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:vorsorgereminder/app/app.dart';
import 'package:vorsorgereminder/app/providers.dart';
import 'package:vorsorgereminder/data/catalog_repository.dart';
import 'package:vorsorgereminder/data/database.dart';
import 'package:vorsorgereminder/data/database_provider.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/l10n/locale_notifier.dart';

/// Reads the catalogs from the repository rather than from a bundled asset, so
/// what the tests exercise is the file that actually ships.
///
/// The read is synchronous on purpose: a widget test runs on a fake clock, and
/// a real file read would complete on the real event loop, which pumping
/// frames never advances.
class DiskAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.view(File(key).readAsBytesSync().buffer);
}

/// Today, pinned. Nothing in a test may read the wall clock, or the suite
/// starts failing on its own as the calendar moves.
final pinnedToday = DateTime.utc(2026, 9, 20);

/// pumpAndSettle waits for every animation to finish, and a progress indicator
/// never finishes, so the first frame of any screen would hang it. Pumping a
/// fixed span lets the streams deliver and route transitions complete.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// A ListView only builds what is on screen, so anything further down a
/// timeline has to be scrolled to before it can be found.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(Scrollable).last,
    const Offset(0, -220),
  );
  await settle(tester);
}

/// A widget test that boots the real app against an in-memory database and a
/// fixed clock.
///
/// The teardown lives inside the test body rather than in `addTearDown`,
/// because the binding checks for pending timers before registered teardowns
/// run - and drift schedules one when its stream queries are cancelled. Left
/// to `addTearDown`, every test ends on "a Timer is still pending".
@isTest
void appTest(
  String description,
  Future<void> Function(WidgetTester tester, AppDatabase db) body, {
  List<Person> people = const [],
  DateTime? today,
  Locale? locale,
}) {
  testWidgets(description, (tester) async {
    final database = openInMemoryDatabase();
    for (final person in people) {
      await database.upsertPerson(person);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(() => today ?? pinnedToday),
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository(bundle: DiskAssetBundle()),
          ),
          localeProvider.overrideWith(() => _FixedLocale(locale)),
        ],
        child: const VorsorgereminderApp(),
      ),
    );
    await settle(tester);

    await body(tester, database);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
    await tester.pump(const Duration(seconds: 1));
  });
}

/// Pins the language, so a test asserting on German text does not depend on
/// what locale the machine running it happens to have.
class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this._locale);

  final Locale? _locale;

  @override
  Locale? build() => _locale ?? const Locale('en');
}
