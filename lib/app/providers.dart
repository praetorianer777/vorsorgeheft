import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog_repository.dart';
import '../data/database.dart';
import '../domain/catalog.dart';
import '../domain/completion.dart';
import '../domain/occurrence.dart';
import '../domain/person.dart';
import '../domain/schedule_engine.dart';
import '../export/ics_export_service.dart';
import '../export/share_gateway.dart';
import '../l10n/locale_notifier.dart';
import '../notifications/local_notification_gateway.dart';
import '../notifications/notification_gateway.dart';
import '../notifications/reminder_service.dart';
import '../sync/bundle_service.dart';
import '../sync/lan_transport.dart';
import '../sync/replicated_store.dart';
import '../sync/sync_protocol.dart';
import '../sync/sync_transport.dart';
import '../ui/qr_scanner.dart';

/// Overridden at startup with the opened database, and in tests with an
/// in-memory one.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Every write goes through here. Overridden at startup alongside the
/// database, so that a local edit and one arriving from the other parent's
/// phone take the same path.
final storeProvider = Provider<ReplicatedStore>(
  (ref) => throw UnimplementedError('storeProvider must be overridden'),
);

/// The platform notification service. Overridden in tests with one that
/// records what it was asked to do.
final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => LocalNotificationGateway(),
);

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    database: ref.watch(databaseProvider),
    gateway: ref.watch(notificationGatewayProvider),
    catalogs: ref.watch(catalogRepositoryProvider),
    locale: () =>
        ref.read(localeProvider) ??
        WidgetsBinding.instance.platformDispatcher.locale,
    clock: () => ref.watch(clockProvider)().toLocal(),
  ),
);

/// The platform share sheet. Overridden in tests with one that keeps the
/// file instead of handing it to a chooser that does not exist there.
final shareGatewayProvider = Provider<ShareGateway>(
  (ref) => const PlatformShareGateway(),
);

final icsExportServiceProvider = Provider<IcsExportService>(
  (ref) => IcsExportService(
    database: ref.watch(databaseProvider),
    catalogs: ref.watch(catalogRepositoryProvider),
    share: ref.watch(shareGatewayProvider),
    clock: () => ref.watch(clockProvider)(),
  ),
);

/// How the other phone is reached. Overridden in tests with a loopback
/// transport, so two app instances can pair and sync inside one test.
final syncTransportProvider = Provider<SyncTransport>((ref) => LanTransport());

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    store: ref.watch(storeProvider),
    registry: ref.watch(databaseProvider),
    transport: ref.watch(syncTransportProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The camera. Overridden in tests with one that answers with a given code.
final qrScannerProvider = Provider<QrScanner>((ref) => const CameraQrScanner());

/// The file chooser. Overridden in tests with one that answers with given
/// bytes.
final bundlePickerProvider = Provider<BundlePicker>(
  (ref) => const PlatformBundlePicker(),
);

final bundleServiceProvider = Provider<BundleService>(
  (ref) => BundleService(
    store: ref.watch(storeProvider),
    share: ref.watch(shareGatewayProvider),
    picker: ref.watch(bundlePickerProvider),
  ),
);

final peersProvider = StreamProvider<List<Peer>>(
  (ref) => ref.watch(databaseProvider).watchPeers(),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => const CatalogRepository(),
);

/// Reading the clock goes through a provider so a test can pin today without
/// the rest of the app knowing.
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final catalogsProvider = FutureProvider<CatalogSet>(
  (ref) => ref.watch(catalogRepositoryProvider).load(),
);

final personsProvider = StreamProvider<List<Person>>(
  (ref) => ref.watch(databaseProvider).watchPersons(),
);

final completionsProvider = StreamProvider<List<Completion>>(
  (ref) => ref.watch(databaseProvider).watchCompletions(),
);

final personProvider = Provider.family<Person?, String>((ref, id) {
  final persons = ref.watch(personsProvider).value ?? const [];
  for (final person in persons) {
    if (person.id == id) return person;
  }
  return null;
});

/// One person's appointments, recomputed whenever anything they depend on
/// changes. Nothing here is stored: the timeline is a view of the date of
/// birth, the catalogs and what has been recorded.
final timelineProvider = Provider.family<AsyncValue<List<Occurrence>>, String>((
  ref,
  personId,
) {
  final catalogs = ref.watch(catalogsProvider);
  final completions = ref.watch(completionsProvider);
  final person = ref.watch(personProvider(personId));

  if (person == null) return const AsyncValue.data([]);

  return catalogs.whenData(
    (catalogSet) => computeOccurrences(
      person: person,
      catalogs: catalogSet,
      completions: completions.value ?? const [],
      today: ref.watch(clockProvider)(),
    ),
  );
});

/// How many appointments across the whole family need attention, for the badge
/// on the family list.
final familyAttentionProvider = Provider.family<int, String>((ref, personId) {
  final occurrences = ref.watch(timelineProvider(personId)).value;
  if (occurrences == null) return 0;
  return occurrences
      .where(
        (o) =>
            o.status == OccurrenceStatus.due ||
            o.status == OccurrenceStatus.overdue,
      )
      .length;
});
