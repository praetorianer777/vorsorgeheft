import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_gateway.dart';
import 'reminder.dart';

/// The platform notification service, as this app uses it.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'appointments';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _exactAllowed = false;

  @override
  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<bool> canScheduleExactly() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return _exactAllowed =
        await android?.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> schedule(
    PlannedReminder reminder, {
    required String title,
    required String body,
    required String channelName,
  }) => _plugin.zonedSchedule(
    id: reminder.id,
    title: title,
    body: body,
    payload: reminder.occurrenceKey,
    scheduledDate: tz.TZDateTime.from(reminder.fireAt, tz.local),
    // Appointments are day-precise, so the inexact mode is enough and needs no
    // special access. Exact alarms are used only where the user has already
    // allowed them.
    androidScheduleMode: _exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        channelName,
        importance: reminder.kind == ReminderKind.deadlineApproaching
            ? Importance.high
            : Importance.defaultImportance,
        priority: reminder.kind == ReminderKind.deadlineApproaching
            ? Priority.high
            : Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );

  @override
  Future<List<int>> pendingIds() async =>
      (await _plugin.pendingNotificationRequests()).map((r) => r.id).toList();
}
