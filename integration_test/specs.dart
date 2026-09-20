import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/completion.dart';
import 'package:vorsorgereminder/notifications/reminder.dart';

import '../test/support/recording_gateway.dart';

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

  testWidgets("an adult gets none of the children's check-ups", (tester) async {
    // Tim was born on a leap day in 1960, so this also exercises the date
    // arithmetic against a real platform rather than only the unit tests.
    final db = await launchApp(tester, people: [Family.father]);
    final timeline = await FamilyPage(tester).open('Tim');

    expect(timeline.needsAttention, findsNothing);
    expect(timeline.noLongerAvailable, findsNothing);
    expect(find.text('U1'), findsNothing);

    await shutDown(tester, db);
  });
}
