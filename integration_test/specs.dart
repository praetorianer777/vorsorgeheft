import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';
import 'package:vorsorgeheft/sync/sync_transport.dart';

import '../test/support/recording_gateway.dart';
import '../test/support/recording_share.dart';

import 'fixtures/family.dart';
import 'helpers/app_harness.dart';
import 'helpers/pages.dart';
import 'helpers/patched_assets.dart';

/// Every end-to-end spec, registered rather than run.
///
/// The same specs run under two bindings: headless under `flutter test`, where
/// they gate every push, and on a real device or emulator under
/// `flutter test integration_test/`, which runs nightly. A spec that only ever
/// ran on the emulator would be written once and then left to rot, because
/// nobody waits four minutes for an emulator before pushing.
void registerAppSpecs() {
  testWidgets('an empty family says what to do next', (tester) async {
    final db = await launchApp(tester);
    expect(FamilyPage(tester).emptyState, findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('a person added through the form gets a schedule', (
    tester,
  ) async {
    final db = await launchApp(tester);
    final family = FamilyPage(tester);

    final form = await family.addPerson();
    await form.save();
    expect(form.nameError, findsOneWidget);
    expect(form.dateError, findsOneWidget);

    await form.enterName('Mila');
    await form.pickDateOfBirth('09/01/2026');
    await form.save();

    expect(family.personNamed('Mila'), findsOneWidget);

    final timeline = await family.open('Mila');
    expect(timeline.needsAttention, findsOneWidget);
    await timeline.scrollToAppointment('U6');
    expect(find.text('U6'), findsOneWidget);
    // The J1 at twelve is not "coming up" for a newborn.
    await scrollTo(tester, timeline.farAhead);
    await timeline.scrollToAppointment('J1');
    expect(timeline.status('J1', 'Upcoming'), findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('an appointment names the guideline it came from', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');
    final appointment = await timeline.open('U6');

    expect(appointment.source, findsOneWidget);
    expect(
      find.textContaining('G-BA guideline on early detection'),
      findsOneWidget,
    );
    expect(appointment.catchUpBy, findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('an exclusion deadline that has passed is shown as expired', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');

    // The U2 tolerance ends on the fourteenth day of life, and Mila is
    // nineteen days old on the pinned today.
    await timeline.scrollToAppointment('U2');
    expect(find.text('Expired'), findsWidgets);

    await shutDown(tester, db);
  });

  testWidgets('recording an appointment settles it, and undo brings it back', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');

    final appointment = await timeline.open('U3');
    await appointment.markDone();
    expect(appointment.statusText('Done'), findsOneWidget);
    expect((await db.allCompletions()).single.ruleId, 'u3');

    await appointment.undo();
    expect(await db.allCompletions(), isEmpty);

    await shutDown(tester, db);
  });

  testWidgets('a skip is recorded as a decision, not as done', (tester) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');
    final appointment = await timeline.open('U3');

    await appointment.markSkipped();
    final recorded = (await db.allCompletions()).single;
    expect(recorded.skipped, isTrue);
    expect(appointment.statusText('Skipped'), findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('what one person has done does not settle another', (
    tester,
  ) async {
    final db = await launchApp(
      tester,
      people: [Family.infant, Family.schoolAge],
    );
    await db.recordCompletion(
      Completion(
        personId: 'infant',
        ruleId: 'u3',
        completedOn: DateTime.utc(2026, 9, 25),
      ),
    );
    await settle(tester);

    final jonas = await FamilyPage(tester).open('Jonas');
    await jonas.scrollToAppointment('U9');
    expect(find.text('Done'), findsNothing);

    await shutDown(tester, db);
  });

  testWidgets('a non-statutory examination says so', (tester) async {
    final db = await launchApp(tester, people: [Family.schoolAge]);
    final timeline = await FamilyPage(tester).open('Jonas');
    await timeline.scrollToAppointment('U10');

    expect(find.text('Depends on your insurer'), findsWidgets);

    await shutDown(tester, db);
  });

  testWidgets('the app explains itself, with the source documents linked', (
    tester,
  ) async {
    final db = await launchApp(tester);
    final settings = await FamilyPage(tester).openSettings();
    final how = await settings.openHowItWorks();
    expect(how.title, findsOneWidget);

    expect(how.section('Where the appointments come from'), findsOneWidget);
    expect(how.sourceLink('https://www.g-ba.de/richtlinien/15/'), findsWidgets);
    await how.reveal(how.legendOverdue);
    expect(how.legendOverdue, findsOneWidget);
    await how.reveal(how.reminders);
    expect(how.reminders, findsOneWidget);
    await how.reveal(how.section('When a guideline changes'));
    expect(how.section('When a guideline changes'), findsOneWidget);

    final sources = await how.openSources();
    expect(
      sources.sourceNamed('G-BA guideline on early detection'),
      findsWidgets,
    );

    await shutDown(tester, db);
  });

  testWidgets('the sources screen carries every citation and the disclaimer', (
    tester,
  ) async {
    final db = await launchApp(tester);
    final sources = await FamilyPage(tester).openSources();

    expect(
      sources.sourceNamed("Children's check-ups, version"),
      findsOneWidget,
    );
    expect(
      sources.sourceNamed('G-BA guideline on early detection'),
      findsOneWidget,
    );
    await sources.scrollToDisclaimer();
    expect(sources.disclaimer, findsOneWidget);
    expect(sources.privacy, findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('a family gets reminders, within the platform limit', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(tester, people: Family.all, gateway: gateway);

    expect(gateway.initialized, isTrue);
    expect(gateway.permissionAsked, isTrue);
    expect(gateway.pending, isNotEmpty);
    // iOS keeps only the 64 notifications that fire soonest and drops the rest
    // without saying so, which is why the app schedules a rolling window.
    expect(gateway.pending.length, lessThanOrEqualTo(20));
    expect(gateway.pending.every((r) => r.fireAt.isAfter(pinnedToday)), isTrue);

    await shutDown(tester, db);
  });

  testWidgets('recording an appointment takes its reminders with it', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant],
      gateway: gateway,
    );

    final before = gateway.pending.where((r) => r.ruleId == 'u3').length;
    expect(before, greaterThan(0));

    final timeline = await FamilyPage(tester).open('Mila');
    final appointment = await timeline.open('U3');
    await appointment.markDone();

    expect(gateway.pending.where((r) => r.ruleId == 'u3'), isEmpty);
    expect(gateway.cancelAllCount, greaterThan(1));

    await shutDown(tester, db);
  });

  testWidgets('reminders follow the time and lead times chosen in settings', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant],
      gateway: gateway,
    );
    expect(gateway.pending.every((r) => r.fireAt.hour == 9), isTrue);
    expect(gateway.pending.any((r) => r.leadTime.inDays == 14), isTrue);

    final settings = await FamilyPage(tester).openSettings();
    await settings.pickReminderTime(hour: 7, minute: 30);
    expect(settings.reminderTime('7:30 AM'), findsOneWidget);
    await settings.toggleLead(14);

    expect(gateway.pending, isNotEmpty);
    expect(
      gateway.pending.every((r) => r.fireAt.hour == 7 && r.fireAt.minute == 30),
      isTrue,
    );
    expect(gateway.pending.any((r) => r.leadTime.inDays == 14), isFalse);

    await settings.toggleReminders();
    expect(gateway.pending, isEmpty);

    // The choice belongs to this phone and survives a restart.
    await detach(tester);
    await launchApp(tester, gateway: gateway, database: db);
    expect(gateway.pending, isEmpty);
    final again = await FamilyPage(tester).openSettings();
    await again.toggleReminders();
    expect(gateway.pending, isNotEmpty);
    expect(gateway.pending.every((r) => r.fireAt.hour == 7), isTrue);

    await shutDown(tester, db);
  });

  testWidgets('deleting a person takes their appointments and reminders', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant, Family.mother],
      gateway: gateway,
    );
    expect(gateway.pending.any((r) => r.personId == 'infant'), isTrue);

    final timeline = await FamilyPage(tester).open('Mila');
    var form = await timeline.edit();
    await form.delete();
    expect(find.text('Delete Mila?'), findsOneWidget);
    await form.cancelDelete();
    expect(form.deleteButton, findsOneWidget);
    await form.delete();
    await form.confirmDelete();

    final family = FamilyPage(tester);
    expect(family.personNamed('Mila'), findsNothing);
    expect(family.personNamed('Sara'), findsOneWidget);
    expect((await db.allPersons()).map((p) => p.name), ['Sara']);
    expect(gateway.pending.any((r) => r.personId == 'infant'), isFalse);
    expect(gateway.pending, isNotEmpty);

    await detach(tester);
    await launchApp(tester, gateway: gateway, database: db);
    expect(FamilyPage(tester).personNamed('Mila'), findsNothing);
    // A new person is not the old one: the form has no delete before saving.
    form = await FamilyPage(tester).addPerson();
    expect(form.deleteButton, findsNothing);

    await shutDown(tester, db);
  });

  testWidgets('a lapsing entitlement is warned about more urgently', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant],
      gateway: gateway,
    );

    final deadlineWarnings = gateway.scheduled.where(
      (s) => s.$1.kind == ReminderKind.deadlineApproaching,
    );
    expect(deadlineWarnings, isNotEmpty);
    expect(
      deadlineWarnings.every((s) => s.$3.contains('no longer covered')),
      isTrue,
    );

    await shutDown(tester, db);
  });

  testWidgets('the schedule exports as a calendar a second import matches', (
    tester,
  ) async {
    final share = RecordingShareGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant, Family.schoolAge],
      share: share,
    );

    await FamilyPage(tester).exportCalendar(share);
    final first = share.lastContent;

    expect(first, startsWith('BEGIN:VCALENDAR'));
    expect(first, contains('SUMMARY:Mila: U6'));
    expect(first, contains('SUMMARY:Jonas: U10'));

    final uids = RegExp(
      'UID:(.+)',
    ).allMatches(first).map((m) => m.group(1)).toList();
    expect(uids, isNotEmpty);
    expect(uids.toSet().length, uids.length);

    // The point of stable uids: re-exporting produces the same events, so a
    // calendar updates them instead of ending up with two of each.
    await FamilyPage(tester).exportCalendar(share);
    expect(share.lastContent, first);

    await shutDown(tester, db);
  });

  testWidgets('a single person exports only their own appointments', (
    tester,
  ) async {
    final share = RecordingShareGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant, Family.schoolAge],
      share: share,
    );

    final timeline = await FamilyPage(tester).open('Jonas');
    await timeline.exportCalendar(share);

    expect(share.lastContent, contains('SUMMARY:Jonas:'));
    expect(share.lastContent, isNot(contains('SUMMARY:Mila:')));
    expect(share.lastFile.path, endsWith('vorsorge-jonas.ics'));

    await shutDown(tester, db);
  });

  testWidgets('each sex sees the screenings it is entitled to', (tester) async {
    final db = await launchApp(
      tester,
      people: [Family.mother, Family.father],
      today: DateTime.utc(2036, 9, 20),
    );

    final sara = await FamilyPage(tester).open('Sara');
    await sara.scrollToAppointment('Mammography screening');
    expect(find.text('Mammography screening'), findsOneWidget);
    expect(find.text('Prostate and genital examination'), findsNothing);
    await sara.back();

    final tim = await FamilyPage(tester).open('Tim');
    await tim.scrollToAppointment('Prostate and genital examination');
    expect(find.text('Prostate and genital examination'), findsOneWidget);
    expect(find.text('Mammography screening'), findsNothing);

    await shutDown(tester, db);
  });

  testWidgets('an unrecorded sex shows both sets as only possibly applying', (
    tester,
  ) async {
    // Hiding them would silently drop an entitlement; showing them as plainly
    // due would send someone to book something they cannot have.
    final db = await launchApp(tester, people: [Family.unstated]);
    final timeline = await FamilyPage(tester).open('Kim');

    await timeline.scrollToAppointment('Prostate and genital examination');
    expect(find.text('May apply'), findsWidgets);

    await shutDown(tester, db);
  });

  testWidgets('the language chosen in settings survives a restart', (
    tester,
  ) async {
    // No pinned locale here: this is the one spec that has to see the real
    // notifier read its override back out of the database.
    final db = await launchApp(tester, people: [Family.infant], locale: null);
    final settings = await FamilyPage(tester).openSettings();
    expect(settings.title, findsOneWidget);

    await settings.chooseGerman();
    expect(settings.germanTitle, findsOneWidget);
    // Checked after the language switch: the version sits at the end of a
    // list that has grown past the fold, and the radios scroll out with it.
    await settings.scrollToVersion();
    expect(settings.version, findsOneWidget);
    await settings.back();
    expect(find.text('Familie'), findsOneWidget);
    expect(find.text('Family'), findsNothing);

    await detach(tester);
    await launchApp(tester, locale: null, database: db);
    expect(find.text('Familie'), findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('the timeline reads its dates in the chosen language', (
    tester,
  ) async {
    final english = await launchApp(tester, people: [Family.infant]);
    final englishTimeline = await FamilyPage(tester).open('Mila');
    await englishTimeline.scrollToAppointment('U3');
    expect(englishTimeline.appointmentDates('Sep 22, 2026'), findsWidgets);
    expect(englishTimeline.appointmentDates('in 2 days'), findsWidgets);
    await shutDown(tester, english);

    final german = await launchApp(
      tester,
      people: [Family.infant],
      locale: const Locale('de'),
    );
    final germanTimeline = await FamilyPage(tester).open('Mila');
    await germanTimeline.scrollToAppointment('U3');
    expect(germanTimeline.appointmentDates('22. Sept. 2026'), findsWidgets);
    expect(germanTimeline.appointmentDates('in 2 Tagen'), findsWidgets);
    await shutDown(tester, german);
  });

  testWidgets('the support prompt appears once, after three appointments', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final family = FamilyPage(tester);
    expect(family.supportPrompt, findsNothing);

    // Recorded from the timeline, the way a parent does it, so the count the
    // prompt reacts to is the one the rest of the app produces.
    for (final title in ['U3', 'U4', 'U5']) {
      final timeline = await family.open('Mila');
      final appointment = await timeline.open(title);
      await appointment.markDone();
      await appointment.back();
      await timeline.back();
      expect(
        family.supportPrompt,
        title == 'U5' ? findsOneWidget : findsNothing,
        reason: 'after $title',
      );
    }

    await family.dismissSupportPrompt();
    expect(family.supportPrompt, findsNothing);

    await detach(tester);
    await launchApp(tester, database: db);
    expect(family.supportPrompt, findsNothing);
    // The link itself stays where it can always be found.
    final settings = await family.openSettings();
    await settings.scrollToSupportLink();
    expect(settings.supportLink, findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('a problem can be reported from settings', (tester) async {
    // url_launcher opens nothing under test, so the spec stops at the tile;
    // what the tile opens is pinned down by test/support/problem_report_test.
    final db = await launchApp(tester, people: [Family.infant]);
    final settings = await FamilyPage(tester).openSettings();
    await settings.scrollToReportProblem();
    expect(settings.reportProblem, findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('a newborn added late is offered the clinic examinations', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');
    expect(timeline.clinicOffer, findsOneWidget);

    await timeline.acceptClinicOffer();
    expect(timeline.clinicOffer, findsNothing);
    final recorded = (await db.allCompletions()).map((c) => c.ruleId).toSet();
    expect(
      recorded,
      containsAll(['u1', 'hearing-screening', 'pulse-oximetry']),
    );
    // The RSV protection is still open, but nothing is overdue any more.
    expect(find.text('Overdue'), findsNothing);

    await detach(tester);
    await launchApp(tester, database: db);
    await FamilyPage(tester).open('Mila');
    expect(timeline.clinicOffer, findsNothing);

    await shutDown(tester, db);
  });

  testWidgets('declining the clinic offer keeps it away', (tester) async {
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');
    await timeline.dismissClinicOffer();
    expect(timeline.clinicOffer, findsNothing);
    expect(await db.allCompletions(), isEmpty);

    await detach(tester);
    await launchApp(tester, database: db);
    await FamilyPage(tester).open('Mila');
    expect(timeline.clinicOffer, findsNothing);

    await shutDown(tester, db);
  });

  testWidgets('what needs attention is ordered by urgency', (tester) async {
    // Mila's newborn examinations are overdue; the RSV protection is merely
    // open. Overdue leads, so the U1 comes before it.
    final db = await launchApp(tester, people: [Family.infant]);
    final timeline = await FamilyPage(tester).open('Mila');
    await timeline.dismissClinicOffer();

    final titles = timeline.visibleTitles();
    expect(titles.first, isNot('RSV protection (infant)'));
    expect(
      titles.indexOf('U1'),
      lessThan(titles.indexOf('RSV protection (infant)')),
    );
    expect(find.textContaining('20 years ago'), findsNothing);

    await shutDown(tester, db);
  });

  testWidgets(
    'dental examinations whose span has passed are no longer offered',
    (tester) async {
      final db = await launchApp(tester, people: [Family.preschooler]);
      final timeline = await FamilyPage(tester).open('Lena');

      expect(timeline.needsAttention, findsOneWidget);
      await timeline.scrollToAppointment('Z4');
      expect(timeline.status('Z4', 'Due'), findsOneWidget);

      await scrollTo(tester, timeline.noLongerAvailable);
      for (final title in ['Z1', 'Z2', 'Z3']) {
        await timeline.scrollToAppointment(title);
        expect(timeline.status(title, 'Expired'), findsOneWidget);
      }
      expect(find.text('Overdue'), findsNothing);

      await shutDown(tester, db);
    },
  );

  testWidgets("an adult gets none of the children's check-ups", (tester) async {
    // Tim was born on a leap day in 1960, so this also exercises the date
    // arithmetic against a real platform rather than only the unit tests.
    final db = await launchApp(tester, people: [Family.father]);
    final timeline = await FamilyPage(tester).open('Tim');

    expect(find.text('U1'), findsNothing);
    expect(find.text('J1'), findsNothing);
    expect(timeline.noLongerAvailable, findsNothing);
    // What a 66-year-old does get: the screenings his age entitles him to.
    await timeline.scrollToAppointment('Abdominal aortic ultrasound');
    expect(find.text('Abdominal aortic ultrasound'), findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets(
    'the app reads in German from the family list to the small print',
    (tester) async {
      final db = await launchApp(
        tester,
        people: [Family.infant],
        locale: const Locale('de'),
      );
      final family = FamilyPage(tester);
      expect(family.titled('Familie'), findsOneWidget);

      final timeline = await family.open('Mila');
      expect(timeline.germanNeedsAttention, findsOneWidget);
      await scrollTo(tester, timeline.germanComingUp);
      expect(timeline.germanComingUp, findsWidgets);

      final appointment = await timeline.open('U3');
      expect(appointment.germanSource, findsOneWidget);
      expect(appointment.germanCatchUpBy, findsOneWidget);
      expect(appointment.germanMarkDone, findsOneWidget);
      await appointment.back();
      await timeline.back();

      final settings = await family.openSettings();
      expect(settings.germanTitle, findsOneWidget);
      final how = await settings.openHowItWorks();
      expect(how.germanTitle, findsOneWidget);
      final sources = await how.openSources();
      expect(sources.germanTitle, findsOneWidget);
      await scrollTo(tester, sources.germanDisclaimer);
      expect(sources.germanDisclaimer, findsOneWidget);

      await shutDown(tester, db);
    },
  );

  testWidgets('editing a person moves their schedule and reminders along', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(
      tester,
      people: [Family.infant],
      gateway: gateway,
    );
    final family = FamilyPage(tester);
    final timeline = await family.open('Mila');

    // Eight days old instead of nineteen: the U2 is back inside its window.
    final form = await timeline.edit();
    await form.enterName('Mila Vogel');
    await form.pickDateOfBirth('09/12/2026');
    await form.save();

    expect(find.text('Mila Vogel'), findsOneWidget);
    await timeline.scrollToAppointment('U2');
    expect(timeline.status('U2', 'Due'), findsOneWidget);
    expect(find.text('Expired'), findsNothing);
    expect(gateway.titles, isNotEmpty);
    expect(gateway.titles.every((t) => t.contains('Mila Vogel')), isTrue);

    await timeline.back();
    expect(family.personNamed('Mila Vogel'), findsOneWidget);
    expect(family.personNamed('Mila'), findsNothing);
    final stored = (await db.personById('infant'))!;
    expect(stored.dateOfBirth, DateTime.utc(2026, 9, 12));

    await shutDown(tester, db);
  });

  testWidgets('an optional vaccination is off until switched on', (
    tester,
  ) async {
    final gateway = RecordingGateway();
    final db = await launchApp(
      tester,
      people: [Family.mother],
      gateway: gateway,
    );
    final timeline = await FamilyPage(tester).open('Sara');
    expect(find.text('Flu vaccination (under 60)'), findsNothing);
    expect(
      gateway.pending.where((r) => r.ruleId == 'influenza-under-60'),
      isEmpty,
    );

    var form = await timeline.edit();
    await form.revealOptionalVaccinations();
    expect(form.optionalVaccinations, findsOneWidget);
    await form.toggleOptional('influenza-under-60');
    await form.save();

    await timeline.scrollToAppointment('Flu vaccination (under 60)');
    expect(
      timeline.status('Flu vaccination (under 60)', 'Due'),
      findsOneWidget,
    );
    expect(find.text('Depends on your insurer'), findsWidgets);
    expect(
      gateway.pending.where((r) => r.ruleId == 'influenza-under-60'),
      isNotEmpty,
    );
    expect((await db.personById('mother'))!.optionalRules, {
      'influenza-under-60',
    });

    form = await timeline.edit();
    await form.toggleOptional('influenza-under-60');
    await form.save();
    expect(find.text('Flu vaccination (under 60)'), findsNothing);
    expect(
      gateway.pending.where((r) => r.ruleId == 'influenza-under-60'),
      isEmpty,
    );
    expect((await db.personById('mother'))!.optionalRules, isEmpty);

    await shutDown(tester, db);
  });

  testWidgets('the pregnancy vaccination is offered to women only', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.mother, Family.father]);
    final family = FamilyPage(tester);

    var timeline = await family.open('Sara');
    var form = await timeline.edit();
    expect(await form.optionalSwitches(), contains('pertussis-pregnancy'));
    await form.save();
    await timeline.back();

    timeline = await family.open('Tim');
    form = await timeline.edit();
    final offered = await form.optionalSwitches();
    expect(offered, isNot(contains('pertussis-pregnancy')));
    expect(offered, contains('tbe'));

    await shutDown(tester, db);
  });

  testWidgets('a school-age child sees what is ahead and what has lapsed', (
    tester,
  ) async {
    // Jonas is eight: the U10 is running, the U11 and J1 lie ahead, and the
    // U9 lapsed a couple of years ago. Nothing is settled yet.
    final db = await launchApp(tester, people: [Family.schoolAge]);
    final timeline = await FamilyPage(tester).open('Jonas');

    expect(timeline.needsAttention, findsOneWidget);
    expect(timeline.status('U10', 'Due'), findsOneWidget);
    await scrollTo(tester, timeline.comingUp);
    for (final title in ['U11', 'J1']) {
      await timeline.scrollToAppointment(title);
      expect(timeline.status(title, 'Upcoming'), findsOneWidget);
    }
    await scrollTo(tester, timeline.noLongerAvailable);
    await timeline.scrollToAppointment('U9');
    expect(timeline.status('U9', 'Expired'), findsOneWidget);
    expect(timeline.settled, findsNothing);

    await shutDown(tester, db);
  });

  testWidgets('a file that is not a bundle is refused, not misread', (
    tester,
  ) async {
    final dad = SyncFixture();
    final db = await launchApp(tester, sync: dad, nodeId: 'dad');
    final sync = await FamilyPage(tester).openSync();
    final notABundle = 'BEGIN:VCALENDAR'.codeUnits;

    await sync.importBundle(dad, notABundle, password: 'correct horse');
    expect(sync.notABundle, findsOneWidget);

    await sync.receiveFromPhone(dad, notABundle, code: '123456');
    expect(sync.notABundle, findsWidgets);
    await sync.back();
    expect(FamilyPage(tester).emptyState, findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('the family name survives a restart and heads the exports', (
    tester,
  ) async {
    final share = RecordingShareGateway();
    final db = await launchApp(tester, people: [Family.infant], share: share);
    final family = FamilyPage(tester);
    expect(family.defaultTitle, findsOneWidget);

    await family.rename('Familie Meier');
    expect(family.titled('Familie Meier'), findsOneWidget);
    expect(family.defaultTitle, findsNothing);

    await family.exportCalendar(share);
    expect(share.lastContent, contains('X-WR-CALNAME:Familie Meier'));
    expect(share.shared.last.$2, 'Familie Meier');
    final sync = await family.openSync();
    await sync.exportBundle(share, password: 'correct horse');
    expect(share.shared.last.$2, 'Familie Meier');
    await sync.back();

    await detach(tester);
    await launchApp(tester, database: db, share: share);
    expect(family.titled('Familie Meier'), findsOneWidget);

    await family.rename('');
    expect(family.defaultTitle, findsOneWidget);
    await family.exportCalendar(share);
    expect(share.shared.last.$2, 'Preventive care – family');

    await shutDown(tester, db);
  });

  testWidgets('the family name reaches the other phone', (tester) async {
    final wire = LoopbackNetwork();
    final mum = SyncFixture(network: wire);
    final dad = SyncFixture(network: wire);

    final mumsDb = await launchApp(tester, sync: mum, nodeId: 'mum');
    await FamilyPage(tester).rename('Haus Sonnenschein');
    final code = await (await FamilyPage(tester).openSync()).showMyCode();
    await detach(tester);
    await mum.stayReachable();

    final dadsDb = await launchApp(tester, sync: dad, nodeId: 'dad');
    expect(FamilyPage(tester).defaultTitle, findsOneWidget);
    final sync = await FamilyPage(tester).openSync();
    await sync.scanCode(dad, code);
    await sync.syncNow('mum');
    await sync.back();
    expect(FamilyPage(tester).titled('Haus Sonnenschein'), findsOneWidget);

    await shutDown(tester, dadsDb);
    await mumsDb.close();
  });

  testWidgets('an optional vaccination switched on reaches the other phone', (
    tester,
  ) async {
    final wire = LoopbackNetwork();
    final mum = SyncFixture(network: wire);
    final dad = SyncFixture(network: wire);

    final mumsDb = await launchApp(
      tester,
      people: [Family.mother],
      sync: mum,
      nodeId: 'mum',
    );
    var timeline = await FamilyPage(tester).open('Sara');
    final form = await timeline.edit();
    await form.toggleOptional('tbe');
    await form.save();
    await timeline.back();
    final code = await (await FamilyPage(tester).openSync()).showMyCode();
    await detach(tester);
    await mum.stayReachable();

    final dadsDb = await launchApp(tester, sync: dad, nodeId: 'dad');
    final sync = await FamilyPage(tester).openSync();
    await sync.scanCode(dad, code);
    await sync.syncNow('mum');
    await sync.back();
    timeline = await FamilyPage(tester).open('Sara');
    await timeline.scrollToAppointment(
      'TBE vaccination (risk areas) · dose 1 of 3',
    );
    expect(
      find.text('TBE vaccination (risk areas) · dose 1 of 3'),
      findsOneWidget,
    );
    expect((await dadsDb.personById('mother'))!.optionalRules, {'tbe'});

    await shutDown(tester, dadsDb);
    await mumsDb.close();
  });

  testWidgets('two phones pair over a code and end up with the same family', (
    tester,
  ) async {
    // One tester shows one app at a time, so the two phones take turns on
    // screen while both stay on the same wire.
    final wire = LoopbackNetwork();
    final mum = SyncFixture(network: wire);
    final dad = SyncFixture(network: wire);

    final mumsDb = await launchApp(
      tester,
      people: [Family.infant],
      sync: mum,
      nodeId: 'mum',
    );
    var sync = await FamilyPage(tester).openSync();
    expect(sync.title, findsOneWidget);
    expect(sync.noDevices, findsOneWidget);
    final code = await sync.showMyCode(deviceName: "Mum's phone");
    await detach(tester);
    await mum.stayReachable();

    final dadsDb = await launchApp(
      tester,
      people: [Family.schoolAge],
      sync: dad,
      nodeId: 'dad',
    );
    sync = await FamilyPage(tester).openSync();
    await sync.scanCode(dad, 'https://example.com/not-a-code');
    expect(sync.invalidCode, findsOneWidget);
    await sync.scanCode(dad, code);
    expect(sync.pairedWith("Mum's phone"), findsOneWidget);
    expect(sync.neverSynced, findsOneWidget);

    await sync.syncNow('mum');
    expect(sync.synced(received: 5, sent: 5), findsOneWidget);
    expect(sync.lastSynced, findsOneWidget);

    await sync.syncNow('mum');
    expect(sync.nothingNew, findsOneWidget);

    await sync.back();
    expect(FamilyPage(tester).personNamed('Mila'), findsOneWidget);
    expect(FamilyPage(tester).personNamed('Jonas'), findsOneWidget);
    await detach(tester);

    await launchApp(tester, sync: mum, nodeId: 'mum', database: mumsDb);
    expect(FamilyPage(tester).personNamed('Mila'), findsOneWidget);
    expect(FamilyPage(tester).personNamed('Jonas'), findsOneWidget);
    sync = await FamilyPage(tester).openSync();
    expect(sync.deviceNamed('Phone'), findsOneWidget);
    expect(sync.lastSynced, findsOneWidget);

    await shutDown(tester, mumsDb);
    await dadsDb.close();
  });

  testWidgets('two untouched phones list each other by model', (tester) async {
    final wire = LoopbackNetwork();
    final pixel = SyncFixture(network: wire);
    final iphone = SyncFixture(network: wire);

    final pixelsDb = await launchApp(
      tester,
      sync: pixel,
      nodeId: 'pixel',
      deviceModel: 'Pixel 8',
    );
    var sync = await FamilyPage(tester).openSync();
    expect(await sync.myName(), 'Pixel 8');
    final code = await sync.showMyCode();
    await detach(tester);
    await pixel.stayReachable();

    final iphonesDb = await launchApp(
      tester,
      sync: iphone,
      nodeId: 'iphone',
      deviceModel: 'iPhone 15',
    );
    sync = await FamilyPage(tester).openSync();
    await sync.scanCode(iphone, code);
    expect(sync.pairedWith('Pixel 8'), findsOneWidget);
    await sync.syncNow('pixel');
    expect(sync.deviceNamed('Pixel 8'), findsOneWidget);
    expect(sync.deviceNamed('iPhone 15'), findsNothing);
    expect(sync.deviceNamed('My phone'), findsNothing);
    await detach(tester);

    await launchApp(
      tester,
      sync: pixel,
      nodeId: 'pixel',
      database: pixelsDb,
      deviceModel: 'Pixel 8',
    );
    sync = await FamilyPage(tester).openSync();
    expect(sync.deviceNamed('iPhone 15'), findsOneWidget);
    expect(sync.deviceNamed('Pixel 8'), findsNothing);
    expect(sync.deviceNamed('My phone'), findsNothing);

    await shutDown(tester, pixelsDb);
    await iphonesDb.close();
  });

  testWidgets('a phone that cannot be found can be given an address', (
    tester,
  ) async {
    final wire = LoopbackNetwork();
    final mum = SyncFixture(network: wire);
    final dad = SyncFixture(network: wire);

    final mumsDb = await launchApp(tester, sync: mum, nodeId: 'mum');
    final code = await (await FamilyPage(tester).openSync()).showMyCode();
    // Mum's phone goes off the network without coming back.
    await detach(tester);

    final dadsDb = await launchApp(tester, sync: dad, nodeId: 'dad');
    final sync = await FamilyPage(tester).openSync();
    await sync.scanCode(dad, code);
    await sync.syncNow('mum');

    expect(sync.addressPrompt, findsOneWidget);
    await sync.enterAddress('192.168.1.20:4321');
    expect(sync.unreachable('My phone'), findsOneWidget);

    await shutDown(tester, dadsDb);
    await mumsDb.close();
  });

  testWidgets(
    'an encrypted file carries the family to a phone on another network',
    (tester) async {
      final share = RecordingShareGateway();
      final mum = SyncFixture();
      final mumsDb = await launchApp(
        tester,
        people: [Family.infant],
        share: share,
        sync: mum,
        nodeId: 'mum',
      );
      var sync = await (await FamilyPage(tester).openSettings()).openSync();
      await sync.exportBundle(share, password: 'correct horse');
      final file = share.lastFile.readAsBytesSync();
      expect(share.lastFile.path, endsWith('.vorsorge'));
      expect(String.fromCharCodes(file), isNot(contains('Mila')));
      await shutDown(tester, mumsDb);

      final dad = SyncFixture();
      final dadsDb = await launchApp(tester, sync: dad, nodeId: 'dad');
      sync = await FamilyPage(tester).openSync();
      await sync.importBundle(dad, file, password: 'battery staple');
      expect(sync.wrongPassword, findsOneWidget);
      expect(FamilyPage(tester).personNamed('Mila'), findsNothing);

      await sync.importBundle(dad, file, password: 'correct horse');
      expect(sync.imported(5), findsOneWidget);
      await sync.back();
      expect(FamilyPage(tester).personNamed('Mila'), findsOneWidget);

      await shutDown(tester, dadsDb);
    },
  );

  testWidgets('a six-digit code carries the family to the other phone', (
    tester,
  ) async {
    final share = RecordingShareGateway();
    final mum = SyncFixture();
    final mumsDb = await launchApp(
      tester,
      people: [Family.infant],
      share: share,
      sync: mum,
      nodeId: 'mum',
    );
    var sync = await FamilyPage(tester).openSync();
    final code = await sync.sendToPhone(share);
    expect(code, matches(RegExp(r'^\d{6}$')));
    final file = share.lastFile.readAsBytesSync();
    expect(share.lastFile.path, endsWith('.vorsorge'));
    expect(String.fromCharCodes(file), isNot(contains('Mila')));
    await shutDown(tester, mumsDb);

    final dad = SyncFixture();
    final dadsDb = await launchApp(tester, sync: dad, nodeId: 'dad');
    sync = await FamilyPage(tester).openSync();
    final wrongCode = code == '000000' ? '000001' : '000000';
    await sync.receiveFromPhone(dad, file, code: wrongCode);
    expect(sync.wrongPassword, findsOneWidget);
    expect(FamilyPage(tester).personNamed('Mila'), findsNothing);

    await sync.receiveFromPhone(dad, file, code: code);
    expect(sync.imported(5), findsOneWidget);
    await sync.back();
    expect(FamilyPage(tester).personNamed('Mila'), findsOneWidget);

    await shutDown(tester, dadsDb);
  });

  testWidgets('a booster recorded today is due on the phone of ten years on', (
    tester,
  ) async {
    // The Td booster is the longest-lived fact the app holds: recorded now,
    // needed in ten years, on a phone that does not exist yet. The file is
    // what carries it, so this spec is the file's round trip through time.
    final share = RecordingShareGateway();
    final oldPhone = SyncFixture();
    final oldDb = await launchApp(
      tester,
      people: [Family.mother],
      share: share,
      sync: oldPhone,
      nodeId: 'old-phone',
    );
    final timeline = await FamilyPage(tester).open('Sara');
    final booster = await timeline.open('Tetanus and diphtheria booster');
    await booster.markDoneOn('03/15/2026');
    // Recording a booster re-keys its occurrence by the recorded date; the
    // detail page must follow it rather than go blank.
    expect(booster.statusText('Done'), findsOneWidget);
    await booster.back();
    await timeline.back();
    var sync = await FamilyPage(tester).openSync();
    await sync.exportBundle(share, password: 'correct horse');
    final file = share.lastFile.readAsBytesSync();
    await shutDown(tester, oldDb);

    final newPhone = SyncFixture();
    final newDb = await launchApp(
      tester,
      today: DateTime.utc(2036, 10, 1),
      sync: newPhone,
      nodeId: 'new-phone',
    );
    sync = await FamilyPage(tester).openSync();
    await sync.importBundle(newPhone, file, password: 'correct horse');
    expect(FamilyPage(tester).syncNotices, findsNothing);
    await sync.back();

    final later = await FamilyPage(tester).open('Sara');
    expect(later.needsAttention, findsOneWidget);
    await later.scrollToAppointment('Tetanus and diphtheria booster');
    expect(later.appointmentDates('Mar 15, 2036'), findsOneWidget);

    await shutDown(tester, newDb);
  });

  testWidgets('the phone whose entry lost is told what replaced it', (
    tester,
  ) async {
    final wire = LoopbackNetwork();
    final mum = SyncFixture(network: wire);
    final dad = SyncFixture(network: wire);

    final mumsDb = await launchApp(
      tester,
      people: [Family.infant],
      sync: mum,
      nodeId: 'mum',
    );
    var timeline = await FamilyPage(tester).open('Mila');
    var appointment = await timeline.open('U3');
    await appointment.markDone();
    await appointment.back();
    await timeline.back();
    var sync = await FamilyPage(tester).openSync();
    final code = await sync.showMyCode();
    await detach(tester);
    await mum.stayReachable();

    // Dad records the same U3 a day later, with a different date.
    final dadsDb = await launchApp(
      tester,
      people: [Family.infant],
      today: pinnedToday.add(const Duration(days: 1)),
      sync: dad,
      nodeId: 'dad',
    );
    timeline = await FamilyPage(tester).open('Mila');
    appointment = await timeline.open('U3');
    await appointment.markDone();
    await appointment.back();
    await timeline.back();
    sync = await FamilyPage(tester).openSync();
    await sync.scanCode(dad, code);
    await sync.syncNow('mum');
    await sync.back();
    // The later entry won, so Dad has nothing to be told.
    expect(FamilyPage(tester).syncNotices, findsNothing);
    await detach(tester);

    await launchApp(tester, sync: mum, nodeId: 'mum', database: mumsDb);
    final family = FamilyPage(tester);
    expect(family.syncNotices, findsOneWidget);
    expect(
      find.text(
        'U3 for Mila: your entry (Sep 20, 2026) was replaced by Sep 21, 2026 '
        'from Phone.',
      ),
      findsOneWidget,
    );
    await family.dismissSyncNotices();
    expect(family.syncNotices, findsNothing);
    await detach(tester);

    await launchApp(tester, sync: mum, nodeId: 'mum', database: mumsDb);
    expect(FamilyPage(tester).syncNotices, findsNothing);

    await shutDown(tester, mumsDb);
    await dadsDb.close();
  });

  testWidgets('an update that changed a catalog is announced once', (
    tester,
  ) async {
    final db = await launchApp(tester, people: [Family.infant]);
    expect(FamilyPage(tester).catalogUpdate, findsNothing);
    await detach(tester);

    // The next launch is the app after an update: the dental catalog comes
    // with a new edition and a note about it.
    final shipped = specAssetBundle;
    specAssetBundle = PatchedAssetBundle(
      shipped ?? rootBundle,
      path: 'assets/catalogs/dental.json',
      patch: (catalog) => {
        ...catalog,
        'catalogVersion': '2027.01',
        '_changes': [
          ...catalog['_changes'] as List,
          {
            'version': '2027.01',
            'en': 'The adult check-up is now twice a year.',
            'de': 'Die Erwachsenen-Kontrolle gibt es jetzt zweimal im Jahr.',
          },
        ],
      },
    );
    addTearDown(() => specAssetBundle = shipped);

    await launchApp(tester, database: db);
    final family = FamilyPage(tester);
    expect(family.catalogUpdate, findsOneWidget);
    expect(
      find.text(
        'Dental check-ups, edition 2027.01: The adult check-up is now twice a '
        'year.',
      ),
      findsOneWidget,
    );
    await family.dismissCatalogUpdate();
    expect(family.catalogUpdate, findsNothing);
    await detach(tester);

    await launchApp(tester, database: db);
    expect(FamilyPage(tester).catalogUpdate, findsNothing);

    await shutDown(tester, db);
  });
}
