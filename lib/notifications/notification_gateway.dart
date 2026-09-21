import 'reminder.dart';

/// What the app needs from the platform's notification service.
///
/// An interface rather than a direct call so the scheduling rules can be
/// tested without a device: the platform limits this code exists to respect
/// are exactly the things an emulator makes slow and awkward to assert.
abstract class NotificationGateway {
  Future<void> initialize();

  /// Asks for permission to post notifications, returning whether it was
  /// granted. Android has required this at runtime since 13, and iOS always
  /// has.
  Future<bool> requestPermission();

  /// Whether the device will deliver at an exact minute. Android reserves that
  /// for apps the user has explicitly allowed; appointments are day-precise,
  /// so being refused costs nothing.
  Future<bool> canScheduleExactly();

  Future<void> cancelAll();

  /// [channelName] is what Android shows in its own notification settings,
  /// so it is passed in localised rather than baked into the gateway.
  Future<void> schedule(
    PlannedReminder reminder, {
    required String title,
    required String body,
    required String channelName,
  });

  Future<List<int>> pendingIds();
}
