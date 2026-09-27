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
  static const _categoryId = 'appointment';
  static const _doneAction = 'done';
  static const _laterAction = 'later';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _exactAllowed = false;
  String _doneLabel = 'Done';
  String _laterLabel = 'Later';

  @override
  Future<void> initialize({
    void Function(ReminderAction action)? onAction,
    String doneLabel = 'Done',
    String laterLabel = 'Later',
  }) async {
    tz_data.initializeTimeZones();
    _doneLabel = doneLabel;
    _laterLabel = laterLabel;
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          // iOS registers its buttons once, here, and a notification refers
          // to them by the category it was posted under.
          notificationCategories: [
            DarwinNotificationCategory(
              _categoryId,
              actions: [
                DarwinNotificationAction.plain(
                  _doneAction,
                  doneLabel,
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  _laterAction,
                  laterLabel,
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _deliver(response, onAction),
    );

    // The app may have been started by the notification itself, in which
    // case the tap happened before there was anything to hand it to.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response != null) _deliver(response, onAction);
    }
  }

  void _deliver(
    NotificationResponse response,
    void Function(ReminderAction action)? onAction,
  ) {
    if (onAction == null) return;
    final payload = ReminderPayload.tryParse(response.payload);
    if (payload == null) return;
    final kind = switch (response.actionId) {
      _doneAction => ReminderActionKind.done,
      _laterAction => ReminderActionKind.later,
      _ => ReminderActionKind.open,
    };
    onAction(ReminderAction(kind, payload));
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
  Future<void> cancel(int id) => _plugin.cancel(id: id);

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
    payload: ReminderPayload.of(reminder).encode(),
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
        actions: [
          // Both open the app: recording from a background isolate would
          // mean a second connection to the same database while the app may
          // be running, which is a race this does not need.
          AndroidNotificationAction(
            _doneAction,
            _doneLabel,
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            _laterAction,
            _laterLabel,
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
        importance: reminder.kind == ReminderKind.deadlineApproaching
            ? Importance.high
            : Importance.defaultImportance,
        priority: reminder.kind == ReminderKind.deadlineApproaching
            ? Priority.high
            : Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(categoryIdentifier: _categoryId),
    ),
  );

  @override
  Future<List<int>> pendingIds() async =>
      (await _plugin.pendingNotificationRequests()).map((r) => r.id).toList();
}
