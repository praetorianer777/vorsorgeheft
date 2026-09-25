import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/app/app.dart';
import 'package:vorsorgeheft/app/providers.dart';
import 'package:vorsorgeheft/data/catalog_repository.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/export/ics_export_service.dart';
import 'package:vorsorgeheft/sync/bundle_service.dart';
import 'package:vorsorgeheft/sync/device_info.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';
import 'package:vorsorgeheft/sync/sync_protocol.dart';
import 'package:vorsorgeheft/sync/sync_transport.dart';
import 'package:vorsorgeheft/l10n/locale_notifier.dart';

import '../../test/support/fake_sync.dart';
import '../../test/support/recording_gateway.dart';
import '../../test/support/recording_share.dart';
import '../fixtures/family.dart';

/// How the specs reach the catalogs.
///
/// Null means the real asset bundle, which is what a device run wants. The
/// headless run sets a synchronous bundle instead: it runs on a fake clock,
/// and a real asset read completes on the real event loop, which pumping
/// frames never advances.
AssetBundle? specAssetBundle;

/// What one app instance of a spec is plugged into: the wire the other
/// instance is on, the camera and the file chooser.
///
/// Two instances of the app cannot run side by side under one tester, so a
/// spec that needs two phones launches them one after the other against
/// their own databases. The wire outlives a launch, which is what lets the
/// first phone stay reachable while the second one is on screen.
class SyncFixture {
  SyncFixture({LoopbackNetwork? network})
    : network = network ?? LoopbackNetwork();

  final LoopbackNetwork network;
  final scanner = FakeQrScanner();
  final picker = FakeBundlePicker();

  /// The engine of the most recent launch on this fixture.
  SyncEngine? engine;

  /// Puts a detached phone back on the wire.
  ///
  /// Detaching disposes the widget tree, which stops the engine the way
  /// closing the app would. The phone a spec put down is still switched on,
  /// though, and has to stay reachable for the one now on screen.
  Future<void> stayReachable() => engine!.start();
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
  Locale? locale = const Locale('en'),
  RecordingGateway? gateway,
  RecordingShareGateway? share,
  AppDatabase? database,
  SyncFixture? sync,
  String nodeId = 'spec-node',
  String? deviceModel,
}) async {
  // A spec asserts on which reminders were planned, not on how a platform
  // renders them, and the emulator makes exactly that assertion slow.
  final activeGateway = gateway ?? RecordingGateway();
  final activeShare = share ?? RecordingShareGateway();
  final activeSync = sync ?? SyncFixture();
  final exportDirectory = Directory.systemTemp.createTempSync('vorsorge-ics');
  addTearDown(() => exportDirectory.deleteSync(recursive: true));
  final db = database ?? openInMemoryDatabase();
  final store = await ReplicatedStore.open(
    db,
    nodeId: nodeId,
    clock: () => today ?? pinnedToday,
  );
  final engine = SyncEngine(
    store: store,
    registry: db,
    transport: LoopbackTransport(activeSync.network),
    clock: () => today ?? pinnedToday,
    // Null stands for a platform that has no model to offer, which is the
    // path that ends in the localised default.
    deviceInfo: FixedDeviceInfo(deviceModel),
  );
  activeSync.engine = engine;
  // Seeding through the store rather than the tables, so a spec exercises the
  // same path a real edit takes.
  for (final person in people) {
    await store.savePerson(person);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        storeProvider.overrideWithValue(store),
        notificationGatewayProvider.overrideWithValue(activeGateway),
        if (specAssetBundle != null)
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository(bundle: specAssetBundle),
          ),
        clockProvider.overrideWithValue(() => today ?? pinnedToday),
        // A share sheet would need a person to dismiss it, and path_provider
        // points at the device's own cache; both are replaced so the spec can
        // read the file that was produced.
        icsExportServiceProvider.overrideWith(
          (ref) => IcsExportService(
            database: db,
            catalogs: specAssetBundle == null
                ? const CatalogRepository()
                : CatalogRepository(bundle: specAssetBundle),
            share: activeShare,
            clock: () => today ?? pinnedToday,
            directory: () async => exportDirectory,
          ),
        ),
        if (locale != null)
          localeProvider.overrideWith(() => _FixedLocale(locale)),
        // No sockets, no camera and no file chooser under a test: the other
        // phone is on an in-memory wire, and both pickers answer with what the
        // spec put in front of them.
        syncEngineProvider.overrideWithValue(engine),
        qrScannerProvider.overrideWithValue(activeSync.scanner),
        bundlePickerProvider.overrideWithValue(activeSync.picker),
        bundleServiceProvider.overrideWith(
          (ref) => BundleService(
            store: store,
            share: activeShare,
            picker: activeSync.picker,
            directory: () async => exportDirectory,
          ),
        ),
      ],
      child: const VorsorgeheftApp(),
    ),
  );
  await settle(tester);
  return db;
}

/// Tears the widget tree down but leaves the database open, so a spec can
/// launch again against it and see what a restart restores.
Future<void> detach(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
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
  // Not dragUntilVisible: it resolves the target to exactly one widget, and a
  // timeline can legitimately show the same section heading or status twice.
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await settle(tester);
  }
  // Found is not the same as on screen: a list builds a little beyond the
  // viewport, so the target can sit just below the bottom edge, where a tap
  // lands outside the render tree and hits nothing.
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await settle(tester);
  }
}

/// Pumps frames until [condition] holds, and returns whether it did.
///
/// A fixed number of frames is the wrong measure on a device: the app runs at
/// its own speed there, so stretching a password takes seconds, a socket
/// answers when it answers, and an assertion made after a set number of
/// frames looks at a screen that has not answered yet. Pumping is what moves
/// both clocks - the fake one a widget test runs on, and the real one, where
/// each pumped frame waits for the device to draw it.
Future<bool> waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final frames = timeout.inMilliseconds ~/ 16;
  for (var i = 0; i < frames && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return condition();
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this._locale);

  final Locale _locale;

  @override
  Locale build() => _locale;
}
