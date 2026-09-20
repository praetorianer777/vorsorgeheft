import 'package:vorsorgereminder/notifications/notification_gateway.dart';
import 'package:vorsorgereminder/notifications/reminder.dart';

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
  int cancelAllCount = 0;
  bool initialized = false;
  bool permissionAsked = false;

  List<PlannedReminder> get pending => scheduled.map((s) => s.$1).toList();
  List<String> get titles => scheduled.map((s) => s.$2).toList();
  List<String> get bodies => scheduled.map((s) => s.$3).toList();

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<bool> requestPermission() async {
    permissionAsked = true;
    return permissionGranted;
  }

  @override
  Future<bool> canScheduleExactly() async => exactAllowed;

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
  }) async => scheduled.add((reminder, title, body));

  @override
  Future<List<int>> pendingIds() async => pending.map((r) => r.id).toList();
}
