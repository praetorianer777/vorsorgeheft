import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/data/catalog_repository.dart';
import 'package:vorsorgereminder/data/database.dart';
import 'package:vorsorgereminder/data/database_provider.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/domain/person.dart';
import 'package:vorsorgereminder/notifications/reminder.dart';
import 'package:vorsorgereminder/notifications/reminder_service.dart';
import 'package:vorsorgereminder/sync/replicated_store.dart';

import '../support/synchronous_assets.dart';
import '../support/recording_gateway.dart';

void main() {
  late AppDatabase db;
  late ReplicatedStore store;
  late RecordingGateway gateway;

  final now = DateTime(2026, 9, 20, 8);
  final newborn = Person(
    id: 'mila',
    name: 'Mila',
    dateOfBirth: DateTime.utc(2026, 9, 1),
  );

  ReminderService serviceWith({
    RecordingGateway? using,
    Locale locale = const Locale('en'),
    ReminderSettings settings = const ReminderSettings(),
  }) => ReminderService(
    database: db,
    gateway: using ?? gateway,
    catalogs: CatalogRepository(bundle: SynchronousAssetBundle()),
    locale: () => locale,
    clock: () => now,
    settings: () => settings,
  );

  setUp(() async {
    db = openInMemoryDatabase();
    store = await ReplicatedStore.open(db, nodeId: 'test', clock: () => now);
    gateway = RecordingGateway();
  });

  tearDown(() => db.close());

  test('with nobody in the family there is nothing to remind about', () async {
    await serviceWith().reschedule();
    expect(gateway.pending, isEmpty);
    expect(gateway.cancelAllCount, 1);
  });

  test('a person with appointments gets reminders', () async {
    await store.savePerson(newborn);
    final plan = await serviceWith().reschedule();

    expect(plan, isNotEmpty);
    expect(gateway.pending.map((r) => r.id), plan.map((r) => r.id));
  });

  test('never more than the cap are pending at once', () async {
    // iOS keeps only the 64 soonest and drops the rest silently, so the app
    // has to stay well inside that and top up rather than schedule everything.
    for (final id in ['a', 'b', 'c', 'd']) {
      await store.savePerson(
        Person(id: id, name: id, dateOfBirth: DateTime.utc(2026, 9, 1)),
      );
    }
    await serviceWith().reschedule();
    expect(gateway.pending.length, lessThanOrEqualTo(20));
  });

  test('the rolling window tops up once the soonest have fired', () async {
    await store.savePerson(newborn);
    var clock = now;
    final service = ReminderService(
      database: db,
      gateway: gateway,
      catalogs: CatalogRepository(bundle: SynchronousAssetBundle()),
      locale: () => const Locale('en'),
      clock: () => clock,
      settings: () => const ReminderSettings(),
    );
    final first = await service.reschedule();
    expect(first, hasLength(20));

    // Past the tenth reminder, the ones that have fired make room for as
    // many later ones, which the first plan had no room for.
    clock = first[9].fireAt.add(const Duration(minutes: 1));
    final second = await service.reschedule();
    final fired = first.where((r) => !r.fireAt.isAfter(clock)).toList();
    final kept = first.where((r) => r.fireAt.isAfter(clock)).map((r) => r.id);

    expect(fired, hasLength(greaterThanOrEqualTo(10)));
    expect(second, hasLength(20));
    expect(second.every((r) => r.fireAt.isAfter(clock)), isTrue);
    final firstIds = first.map((r) => r.id).toSet();
    final secondIds = second.map((r) => r.id).toSet();
    expect(secondIds, containsAll(kept));
    expect(secondIds.difference(firstIds), hasLength(fired.length));
    expect(gateway.pending.map((r) => r.id), second.map((r) => r.id));
  });

  test('rescheduling replaces rather than adds', () async {
    await store.savePerson(newborn);
    final service = serviceWith();
    await service.reschedule();
    final first = gateway.pending.length;

    await service.reschedule();
    expect(gateway.cancelAllCount, 2);
    expect(gateway.pending.length, first);
  });

  test('recording an appointment removes its reminders', () async {
    await store.savePerson(newborn);
    final service = serviceWith();
    await service.reschedule();
    // Whichever appointment is nearest: the rolling window holds the twenty
    // soonest reminders across every catalog, so naming one here would make
    // the test depend on what else happens to be due that week.
    final ruleId = gateway.pending.first.ruleId;
    expect(gateway.pending.where((r) => r.ruleId == ruleId), isNotEmpty);

    await store.recordCompletion(
      Completion(
        personId: 'mila',
        ruleId: ruleId,
        completedOn: DateTime.utc(2026, 9, 20),
      ),
    );
    await service.reschedule();

    expect(gateway.pending.where((r) => r.ruleId == ruleId), isEmpty);
  });

  test('a deleted person takes their reminders with them', () async {
    await store.savePerson(newborn);
    final service = serviceWith();
    await service.reschedule();
    expect(gateway.pending, isNotEmpty);

    await store.deletePerson('mila');
    await service.reschedule();
    expect(gateway.pending, isEmpty);
  });

  test('the text names the person and the appointment', () async {
    await store.savePerson(newborn);
    await serviceWith().reschedule();
    expect(gateway.titles.every((t) => t.contains('Mila')), isTrue);
    expect(gateway.titles.any((t) => t.contains('U')), isTrue);
  });

  test('a deadline warning reads differently from a window reminder', () async {
    await store.savePerson(newborn);
    await serviceWith(
      settings: const ReminderSettings(maxPending: 200),
    ).reschedule();

    final deadline = gateway.scheduled.firstWhere(
      (s) => s.$1.kind == ReminderKind.deadlineApproaching,
    );
    expect(deadline.$2, contains('about to lapse'));
    expect(deadline.$3, contains('no longer covered'));
  });

  test('the text follows the chosen language', () async {
    await store.savePerson(newborn);
    await serviceWith(
      locale: const Locale('de'),
      settings: const ReminderSettings(maxPending: 200),
    ).reschedule();

    expect(gateway.titles.any((t) => t.contains('steht an')), isTrue);
    expect(gateway.titles.any((t) => t.contains('läuft bald ab')), isTrue);
    expect(gateway.bodies.any((b) => b.contains('Zeitraum beginnt')), isTrue);
    // Android shows the channel name in its own settings, so it is localised
    // like everything else the notification carries.
    expect(gateway.channelNames, everyElement('Erinnerungen'));
  });

  group('permissions', () {
    test('nothing is scheduled when permission is refused', () async {
      await store.savePerson(newborn);
      final refused = RecordingGateway(permissionGranted: false);
      final granted = await serviceWith(using: refused).start();

      expect(granted, isFalse);
      expect(refused.permissionAsked, isTrue);
      expect(refused.pending, isEmpty);
    });

    test('starting up asks, then schedules', () async {
      await store.savePerson(newborn);
      final granted = await serviceWith().start();

      expect(granted, isTrue);
      expect(gateway.initialized, isTrue);
      expect(gateway.pending, isNotEmpty);
    });
  });
}
