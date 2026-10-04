import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/data/catalog_repository.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';
import 'package:vorsorgeheft/notifications/notification_gateway.dart';
import 'package:vorsorgeheft/notifications/reminder_service.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';

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

  test('a run that fails does not block the next one', () async {
    // The platform can refuse a notification, and the queue that serialises
    // the runs would carry that error into every later run if it kept it.
    await store.savePerson(newborn);
    gateway.failNextSchedule = true;
    final service = serviceWith();

    await expectLater(service.reschedule(), throwsA(isA<StateError>()));

    final plan = await service.reschedule();
    expect(plan, isNotEmpty);
    expect(gateway.pending.map((r) => r.id), plan.map((r) => r.id));
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

  group('acting on a notification', () {
    /// The button on the lock screen: the service records or puts off, and
    /// then plans again, so the reminder that was acted on is gone.
    Future<PlannedReminder> firstFor(
      ReminderService service,
      String rule,
    ) async {
      final plan = await service.reschedule();
      return plan.firstWhere((r) => r.ruleId == rule);
    }

    test(
      'done records the appointment for today and stops reminding',
      () async {
        await store.savePerson(newborn);
        final service = serviceWith();
        final reminder = await firstFor(service, 'u4');

        await service.act(
          ReminderAction(ReminderActionKind.done, ReminderPayload.of(reminder)),
        );

        final recorded = (await db.allCompletions()).single;
        expect(recorded.ruleId, 'u4');
        expect(recorded.completedOn, DateTime.utc(2026, 9, 20));
        expect(recorded.skipped, isFalse);
        expect(gateway.pending.map((r) => r.ruleId), isNot(contains('u4')));
      },
    );

    test('done on a dose records that dose', () async {
      await store.savePerson(newborn);
      final service = serviceWith();
      final plan = await service.reschedule();
      final dose = plan.firstWhere((r) => r.doseId != null);

      await service.act(
        ReminderAction(ReminderActionKind.done, ReminderPayload.of(dose)),
      );

      final recorded = (await db.allCompletions()).single;
      expect(recorded.ruleId, dose.ruleId);
      expect(recorded.doseId, dose.doseId);
    });

    test('later moves that one reminder three days out', () async {
      await store.savePerson(newborn);
      final service = serviceWith();
      final reminder = await firstFor(service, 'u4');

      await service.act(
        ReminderAction(ReminderActionKind.later, ReminderPayload.of(reminder)),
      );

      final after = gateway.pending.where((r) => r.ruleId == 'u4');
      expect(after, hasLength(1), reason: 'one reminder, not the usual three');
      expect(after.single.fireAt, DateTime(2026, 9, 23, 9));
      // Nothing was recorded: putting off is not doing.
      expect(await db.allCompletions(), isEmpty);
      // And no other appointment was touched.
      expect(gateway.pending.where((r) => r.ruleId != 'u4'), isNotEmpty);
    });

    test('what was put off comes back once its day has passed', () async {
      await store.savePerson(newborn);
      var now = DateTime(2026, 9, 20, 8);
      final service = ReminderService(
        database: db,
        store: store,
        gateway: gateway,
        catalogs: CatalogRepository(bundle: SynchronousAssetBundle()),
        locale: () => const Locale('en'),
        clock: () => now,
        settings: () => const ReminderSettings(),
      );
      final reminder = await firstFor(service, 'u4');
      await service.act(
        ReminderAction(ReminderActionKind.later, ReminderPayload.of(reminder)),
      );

      now = DateTime(2026, 9, 24, 8);
      await service.reschedule();

      expect(
        gateway.pending.where((r) => r.ruleId == 'u4'),
        hasLength(greaterThan(1)),
        reason: 'the usual leads are back',
      );
      expect(await db.settingsUnder('reminder.put-off.'), isEmpty);
    });

    test('recording it elsewhere clears what was put off', () async {
      await store.savePerson(newborn);
      final service = serviceWith();
      final reminder = await firstFor(service, 'u4');
      await service.act(
        ReminderAction(ReminderActionKind.later, ReminderPayload.of(reminder)),
      );
      expect(await db.settingsUnder('reminder.put-off.'), isNotEmpty);

      await store.recordCompletion(
        Completion(
          personId: 'mila',
          ruleId: 'u4',
          completedOn: DateTime.utc(2026, 9, 20),
        ),
      );
      await service.reschedule();

      expect(await db.settingsUnder('reminder.put-off.'), isEmpty);
    });

    test('later again moves it three days from the second time', () async {
      await store.savePerson(newborn);
      var today = DateTime(2026, 9, 20, 8);
      final service = ReminderService(
        database: db,
        store: store,
        gateway: gateway,
        catalogs: CatalogRepository(bundle: SynchronousAssetBundle()),
        locale: () => const Locale('en'),
        clock: () => today,
        settings: () => const ReminderSettings(),
      );
      final reminder = await firstFor(service, 'u4');
      final later = ReminderAction(
        ReminderActionKind.later,
        ReminderPayload.of(reminder),
      );

      await service.act(later);
      expect(
        gateway.pending.singleWhere((r) => r.ruleId == 'u4').fireAt,
        DateTime(2026, 9, 23, 9),
      );

      // It comes back three days later and is put off again: from then,
      // not from the first time it was asked about.
      today = DateTime(2026, 9, 23, 9, 30);
      await service.act(later);
      expect(
        gateway.pending.singleWhere((r) => r.ruleId == 'u4').fireAt,
        DateTime(2026, 9, 26, 9),
      );
      expect(await db.allCompletions(), isEmpty);
    });

    test(
      'recording it from the notification clears what was put off',
      () async {
        await store.savePerson(newborn);
        final service = serviceWith();
        final reminder = await firstFor(service, 'u4');
        final payload = ReminderPayload.of(reminder);

        await service.act(ReminderAction(ReminderActionKind.later, payload));
        expect(await db.settingsUnder('reminder.put-off.'), isNotEmpty);

        await service.act(ReminderAction(ReminderActionKind.done, payload));
        expect(
          await db.settingsUnder('reminder.put-off.'),
          isEmpty,
          reason: 'a row about an appointment that is done is about nothing',
        );
      },
    );

    test('a stored day that is not a date is thrown away', () async {
      await store.savePerson(newborn);
      await db.putSetting('reminder.put-off.mila-u4', 'the day after soon');
      final service = serviceWith();

      await service.reschedule();

      expect(await db.settingsUnder('reminder.put-off.'), isEmpty);
      expect(
        gateway.pending.where((r) => r.ruleId == 'u4'),
        isNotEmpty,
        reason: 'and the appointment is reminded about as usual',
      );
    });

    test('a row about somebody who is gone is thrown away', () async {
      await store.savePerson(newborn);
      final service = serviceWith();
      final reminder = await firstFor(service, 'u4');
      await service.act(
        ReminderAction(ReminderActionKind.later, ReminderPayload.of(reminder)),
      );
      expect(await db.settingsUnder('reminder.put-off.'), isNotEmpty);

      await store.deletePerson('mila');
      await service.reschedule();

      expect(await db.settingsUnder('reminder.put-off.'), isEmpty);
    });

    test('what was put off outlives the app being closed', () async {
      await store.savePerson(newborn);
      final reminder = await firstFor(serviceWith(), 'u4');
      await serviceWith().act(
        ReminderAction(ReminderActionKind.later, ReminderPayload.of(reminder)),
      );

      // A fresh service on the same database is what the next launch has.
      final next = RecordingGateway();
      await serviceWith(using: next).reschedule();

      final after = next.pending.where((r) => r.ruleId == 'u4');
      expect(after, hasLength(1));
      expect(after.single.fireAt, DateTime(2026, 9, 23, 9));
    });

    test('what was put off stays on this phone', () async {
      // Which evening somebody did not feel like reading about an
      // appointment is not something the other phone needs to know, and a
      // reminder put off there would be put off here too.
      await store.savePerson(newborn);
      final service = serviceWith();
      final reminder = await firstFor(service, 'u4');
      final before = (await db.changesAfter(0)).$1.length;

      await service.act(
        ReminderAction(ReminderActionKind.later, ReminderPayload.of(reminder)),
      );

      expect(await db.settingsUnder('reminder.put-off.'), isNotEmpty);
      expect((await db.changesAfter(0)).$1, hasLength(before));
    });

    test('a notification from an older version is ignored', () {
      // Its payload was the bare occurrence key, which is not a payload this
      // version can act on.
      expect(ReminderPayload.tryParse('mila-u4'), isNull);
      expect(ReminderPayload.tryParse(null), isNull);
      expect(ReminderPayload.tryParse('{"key": "mila-u4"}'), isNull);
    });

    test('the buttons are labelled in the chosen language', () async {
      await serviceWith(locale: const Locale('de')).start();
      expect(gateway.doneLabel, 'Erledigt');
      expect(gateway.laterLabel, 'Später');
    });
  });
}
