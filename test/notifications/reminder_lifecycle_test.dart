import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/person.dart';

import '../support/harness.dart';
import '../support/recording_gateway.dart';

/// iOS keeps only the 64 notifications that are nearest in time, so a family
/// with more appointments than that loses the later ones unless the app tops
/// the window up. Coming back to the foreground is the only moment it can
/// reliably do that, and nothing else in the suite covers it.
void main() {
  final gateway = RecordingGateway();

  appTest(
    'coming back to the foreground plans the reminders again',
    people: [
      Person(id: 'mila', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
    ],
    gateway: gateway,
    (tester, db) async {
      final afterStart = gateway.cancelAllCount;
      expect(gateway.pending, isNotEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      expect(gateway.cancelAllCount, afterStart);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(gateway.cancelAllCount, greaterThan(afterStart));
      expect(gateway.pending, isNotEmpty);
    },
  );
}
