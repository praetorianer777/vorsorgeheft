import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vorsorgeheft/notifications/local_notification_gateway.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';

/// Proof that a scheduled reminder is actually posted by the platform.
///
/// The specs only assert which reminders were planned through a recording
/// gateway; nothing there touches the notification service. This test goes
/// through the real plugin on an emulator or device, schedules a reminder a
/// few seconds ahead and reads it back from the shade. It is not registered
/// in `specs.dart` on purpose, so the headless run never sees it. Run
/// nightly by `android-e2e.yml` and `ios-e2e.yml`, or locally with
/// `flutter test integration_test/reminder_on_device_test.dart -d <device>`.
///
/// Notification permission has to be granted before the test starts: asking
/// for it opens a system dialog nobody is there to answer. On Android that is
/// `adb shell pm grant <package> android.permission.POST_NOTIFICATIONS`; on
/// iOS the test asks provisionally, which iOS grants without a prompt.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a reminder scheduled seconds ahead reaches the shade', (
    tester,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      markTestSkipped(
        'the plugin reports active notifications on Android and iOS only',
      );
      return;
    }

    await tester.runAsync(() async {
      final plugin = FlutterLocalNotificationsPlugin();
      final gateway = LocalNotificationGateway(plugin);
      await gateway.initialize();
      await gateway.cancelAll();

      if (Platform.isAndroid) {
        final android = plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!;
        expect(
          await android.areNotificationsEnabled(),
          isTrue,
          reason:
              'POST_NOTIFICATIONS is not granted; grant it before the run '
              'with adb shell pm grant, because asking from here would open '
              'a dialog nobody answers',
        );
      } else {
        final ios = plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()!;
        // Provisional authorisation delivers quietly to Notification Center
        // and needs no user prompt, which is all a simulator can offer.
        await ios.requestPermissions(alert: true, provisional: true);
        final permissions = await ios.checkPermissions();
        if (permissions?.isEnabled != true) {
          markTestSkipped(
            'iOS refused even provisional notification permission, so '
            'nothing can be delivered on this simulator',
          );
          return;
        }
      }

      expect(await gateway.requestPermission(), isTrue);
      await gateway.canScheduleExactly();

      final reminder = PlannedReminder(
        id: reminderId(
          'device-proof',
          ReminderKind.deadlineApproaching,
          const Duration(days: 7),
        ),
        occurrenceKey: 'device-proof',
        personId: 'device-proof',
        ruleId: 'device-proof',
        kind: ReminderKind.deadlineApproaching,
        fireAt: DateTime.now().add(const Duration(seconds: 5)),
        leadTime: const Duration(days: 7),
      );
      await gateway.schedule(
        reminder,
        title: 'Vorsorgeheft device proof',
        body: 'Scheduled by reminder_on_device_test',
        channelName: 'Appointments',
      );
      expect(await gateway.pendingIds(), contains(reminder.id));

      // An inexact alarm may be deferred for minutes, so the wait is generous
      // even though the exact path, which the manifest allows, fires on time.
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      var posted = <ActiveNotification>[];
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        posted = await plugin.getActiveNotifications();
        if (posted.any((n) => n.id == reminder.id)) break;
      }

      expect(
        posted.map((n) => n.id),
        contains(reminder.id),
        reason: 'the reminder was scheduled but never posted',
      );
      final shown = posted.firstWhere((n) => n.id == reminder.id);
      expect(shown.title, 'Vorsorgeheft device proof');
      expect(shown.body, 'Scheduled by reminder_on_device_test');

      await gateway.cancelAll();
    });
  });
}
