import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../data/catalog_repository.dart';
import '../data/database.dart';
import '../domain/occurrence.dart';
import '../domain/person.dart';
import '../domain/schedule_engine.dart';
import '../l10n/app_localizations.dart';
import '../ui/formatting.dart';
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
    DateTime Function()? clock,
    ReminderSettings Function()? settings,
  }) : _db = database,
       _gateway = gateway,
       _catalogs = catalogs,
       _locale = locale,
       _clock = clock ?? DateTime.now,
       _settings = settings ?? (() => const ReminderSettings());

  final AppDatabase _db;
  final NotificationGateway _gateway;
  final CatalogRepository _catalogs;
  final Locale Function() _locale;
  final DateTime Function() _clock;

  /// Read on every run, not once: the person can change the time of day or
  /// switch reminders off while the app is open, and the next plan has to
  /// follow.
  final ReminderSettings Function() _settings;

  Future<bool> start() async {
    await _gateway.initialize();
    final granted = await _gateway.requestPermission();
    await _gateway.canScheduleExactly();
    if (granted) await reschedule();
    return granted;
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

  Future<List<PlannedReminder>> _reschedule() async {
    final now = _clock();
    final catalogs = await _catalogs.load();
    final completions = await _db.allCompletions();
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
          today: DateTime.utc(now.year, now.month, now.day),
        ),
      );
    }

    final byKey = {for (final o in occurrences) o.key: o};
    final plan = planReminders(
      occurrences: occurrences,
      now: now,
      settings: _settings(),
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
