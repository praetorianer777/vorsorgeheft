import 'package:vorsorgeheft/notifications/notification_gateway.dart';
import 'package:vorsorgeheft/notifications/reminder.dart';

/// A notification service that remembers what it was asked to do.
///
/// The rules worth testing here are about how many notifications are pending
/// and which ones, not about how a platform renders them, and an emulator
/// makes exactly those assertions slow and awkward.
class RecordingGateway implements NotificationGateway {
  RecordingGateway({this.permissionGranted = true, this.exactAllowed = false});

  final bool permissionGranted;
  final bool exactAllowed;

  final List<(PlannedReminder, String, String)> scheduled = [];
  final List<String> channelNames = [];
  int cancelAllCount = 0;

  /// Makes the next [schedule] throw, the way a platform that refuses a
  /// notification does.
  bool failNextSchedule = false;
  bool initialized = false;
  bool permissionAsked = false;

  List<PlannedReminder> get pending => scheduled.map((s) => s.$1).toList();
  List<String> get titles => scheduled.map((s) => s.$2).toList();
  List<String> get bodies => scheduled.map((s) => s.$3).toList();

  /// The buttons the platform was told to put on a notification, and the
  /// callback it would deliver a press to.
  String? doneLabel;
  String? laterLabel;
  void Function(ReminderAction action)? onAction;

  final List<int> cancelled = [];

  @override
  Future<void> initialize({
    void Function(ReminderAction action)? onAction,
    String doneLabel = 'Done',
    String laterLabel = 'Later',
  }) async {
    initialized = true;
    this.onAction = onAction;
    this.doneLabel = doneLabel;
    this.laterLabel = laterLabel;
  }

  /// Presses a button on a notification that is pending, the way the person
  /// would from the lock screen.
  void press(ReminderActionKind kind, PlannedReminder reminder) =>
      onAction?.call(ReminderAction(kind, ReminderPayload.of(reminder)));

  @override
  Future<bool> requestPermission() async {
    permissionAsked = true;
    return permissionGranted;
  }

  @override
  Future<bool> canScheduleExactly() async => exactAllowed;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.removeWhere((s) => s.$1.id == id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduled.clear();
  }

  @override
  Future<void> schedule(
    PlannedReminder reminder, {
    required String title,
    required String body,
    required String channelName,
  }) async {
    if (failNextSchedule) {
      failNextSchedule = false;
      throw StateError('the platform refused this notification');
    }
    channelNames.add(channelName);
    scheduled.add((reminder, title, body));
  }

  @override
  Future<List<int>> pendingIds() async => pending.map((r) => r.id).toList();
}
