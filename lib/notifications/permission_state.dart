import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device will actually deliver a reminder.
///
/// Null until asked. Worth showing, because an app that is silently never
/// allowed to notify looks identical to one with nothing due - and the whole
/// point of this app is the appointment nobody reminded you about.
class NotificationPermission extends Notifier<bool?> {
  @override
  bool? build() => null;

  void set({required bool granted}) => state = granted;
}

final notificationPermissionProvider =
    NotifierProvider<NotificationPermission, bool?>(NotificationPermission.new);
