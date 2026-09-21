import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/notifications/reminder.dart';

import '../test/support/recording_gateway.dart';
import '../test/support/recording_share.dart';

import 'fixtures/family.dart';
import 'helpers/app_harness.dart';
import 'helpers/pages.dart';

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
    expect(settings.version, findsOneWidget);

    await settings.chooseGerman();
    expect(settings.germanTitle, findsOneWidget);
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
    expect(settings.supportLink, findsOneWidget);

    await shutDown(tester, db);
  });

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
}
