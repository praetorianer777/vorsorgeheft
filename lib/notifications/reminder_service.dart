import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../data/catalog_repository.dart';
import '../data/database.dart';
import '../domain/occurrence.dart';
import '../domain/person.dart';
import '../domain/schedule_engine.dart';
import '../l10n/app_localizations.dart';
import '../sync/replicated_store.dart';
import '../ui/formatting.dart';
import '../domain/completion.dart';
import 'notification_gateway.dart';
import 'reminder.dart';

/// Keeps the pending notifications in step with what is actually due.
///
/// Rescheduling replaces the whole set rather than patching it. The set is
/// small by design, and working out which of twenty notifications changed
/// after an appointment was recorded is more ways to be wrong than simply
/// planning again from what is true now.
class ReminderService {
  ReminderService({
    required AppDatabase database,
    required NotificationGateway gateway,
    required CatalogRepository catalogs,
    required Locale Function() locale,
    ReplicatedStore? store,
    DateTime Function()? clock,
    ReminderSettings Function()? settings,
  }) : _db = database,
       _store = store,
       _gateway = gateway,
       _catalogs = catalogs,
       _locale = locale,
       _clock = clock ?? DateTime.now,
       _settings = settings ?? (() => const ReminderSettings());

  final AppDatabase _db;

  /// Recording from a notification writes through the store, so the other
  /// phone learns about it like any other change. Null in the tests that
  /// only plan reminders.
  final ReplicatedStore? _store;
  final NotificationGateway _gateway;
  final CatalogRepository _catalogs;
  final Locale Function() _locale;
  final DateTime Function() _clock;

  /// Read on every run, not once: the person can change the time of day or
  /// switch reminders off while the app is open, and the next plan has to
  /// follow.
  final ReminderSettings Function() _settings;

  /// How long "later" puts a reminder off. Long enough that the person is
  /// not asked again the same evening, short enough that a window does not
  /// close in between.
  static const putOffBy = Duration(days: 3);

  static const _putOffPrefix = 'reminder.put-off.';

  /// [onHandled] is called once this service has done its part, so the app
  /// can open the appointment or say what it recorded.
  Future<bool> start({void Function(ReminderAction action)? onHandled}) async {
    final l10n = lookupAppLocalizations(_locale());
    await _gateway.initialize(
      doneLabel: l10n.reminderActionDone,
      laterLabel: l10n.reminderActionLater,
      onAction: (action) => act(action, onHandled: onHandled),
    );
    final granted = await _gateway.requestPermission();
    await _gateway.canScheduleExactly();
    if (granted) await reschedule();
    return granted;
  }

  /// Carries out what the person chose on the notification.
  ///
  /// Recording and putting off both happen here rather than in a background
  /// isolate: a second connection to the same database while the app may be
  /// open is a race this feature does not need, and both actions bring the
  /// app to the front anyway.
  Future<void> act(
    ReminderAction action, {
    void Function(ReminderAction action)? onHandled,
  }) async {
    final payload = action.payload;
    switch (action.kind) {
      case ReminderActionKind.open:
        break;
      case ReminderActionKind.done:
        final now = _clock();
        await _record(payload, DateTime.utc(now.year, now.month, now.day));
        await _db.deleteSetting('$_putOffPrefix${payload.occurrenceKey}');
        await reschedule();
      case ReminderActionKind.later:
        final until = _clock().add(putOffBy);
        await _db.putSetting(
          '$_putOffPrefix${payload.occurrenceKey}',
          DateTime.utc(until.year, until.month, until.day).toIso8601String(),
        );
        await reschedule();
    }
    onHandled?.call(action);
  }

  Future<void> _record(ReminderPayload payload, DateTime on) async {
    final completion = Completion(
      personId: payload.personId,
      ruleId: payload.ruleId,
      doseId: payload.doseId,
      completedOn: on,
    );
    final store = _store;
    if (store == null) {
      await _db.recordCompletion(completion);
    } else {
      await store.recordCompletion(completion);
    }
  }

  Future<List<PlannedReminder>> _queue = Future.value(const []);

  /// Rescheduling cancels everything pending and schedules the plan again.
  /// Two runs overlapping would cancel once and schedule twice, leaving double
  /// the notifications, so they are serialised. A failed run must not block
  /// the next one, which is why the chain swallows its error rather than the
  /// caller's.
  Future<List<PlannedReminder>> reschedule() {
    final next = _queue.then((_) => _reschedule());
    _queue = next.then(
      (plan) => plan,
      onError: (_) => const <PlannedReminder>[],
    );
    return next;
  }

  /// The appointments the person asked to be reminded about later, minus
  /// the ones that are settled or whose day has come: a row that is no
  /// longer about anything is dropped rather than kept forever.
  Future<Map<String, DateTime>> _putOff(
    Set<String> stillOpen,
    DateTime now,
  ) async {
    final stored = await _db.settingsUnder(_putOffPrefix);
    final live = <String, DateTime>{};
    for (final entry in stored.entries) {
      final key = entry.key.substring(_putOffPrefix.length);
      final until = DateTime.tryParse(entry.value);
      if (until == null || !stillOpen.contains(key) || until.isBefore(now)) {
        await _db.deleteSetting(entry.key);
        continue;
      }
      live[key] = until;
    }
    return live;
  }

  Future<List<PlannedReminder>> _reschedule() async {
    final now = _clock();
    final catalogs = await _catalogs.load();
    final completions = await _db.allCompletions();
    final ownAppointments = await _db.allOwnAppointments();
    final persons = await _db.allPersons();

    final occurrences = <Occurrence>[];
    final people = <String, Person>{};
    for (final person in persons) {
      people[person.id] = person;
      occurrences.addAll(
        computeOccurrences(
          person: person,
          catalogs: catalogs,
          completions: completions,
          ownAppointments: ownAppointments,
          today: DateTime.utc(now.year, now.month, now.day),
        ),
      );
    }

    final byKey = {for (final o in occurrences) o.key: o};
    final plan = planReminders(
      occurrences: occurrences,
      now: now,
      settings: _settings(),
      putOff: await _putOff({
        for (final occurrence in occurrences)
          if (occurrence.isOpen) occurrence.key,
      }, now),
    );

    await _gateway.cancelAll();

    final language = _locale().languageCode;
    // Outside a widget tree there is no localisation delegate to do this, and
    // this service also runs from a background task, where formatting a date
    // would otherwise throw.
    await initializeDateFormatting(language);
    final l10n = lookupAppLocalizations(_locale());

    for (final reminder in plan) {
      final occurrence = byKey[reminder.occurrenceKey]!;
      final name = people[reminder.personId]?.name ?? '';
      final appointment = occurrenceTitle(l10n, language, occurrence);

      await _gateway.schedule(
        reminder,
        title: reminder.kind == ReminderKind.deadlineApproaching
            ? l10n.reminderDeadlineTitle(name, appointment)
            : l10n.reminderWindowOpensTitle(name, appointment),
        body: reminder.kind == ReminderKind.deadlineApproaching
            ? l10n.reminderDeadlineBody(occurrence.deadline!)
            : l10n.reminderWindowOpensBody(occurrence.windowStart),
        channelName: l10n.notificationsTitle,
      );
    }
    return plan;
  }
}
