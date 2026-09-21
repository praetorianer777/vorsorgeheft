import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'permission_state.dart';
import 'reminder_preferences_notifier.dart';

/// Keeps the pending notifications in step with the data.
///
/// Rescheduling is driven from here rather than from each place that writes,
/// so a new screen that records something cannot forget to do it. It is also
/// where the app tops the rolling window up on every start, which is what
/// keeps a family with more appointments than iOS will hold from losing the
/// later ones.
class ReminderSync extends ConsumerStatefulWidget {
  const ReminderSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends ConsumerState<ReminderSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await ref.read(reminderServiceProvider).start();
      if (mounted) {
        ref.read(notificationPermissionProvider.notifier).set(granted: granted);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the app's only reliable chance to top
    // the rolling window up on iOS, where background execution is not
    // guaranteed.
    if (state == AppLifecycleState.resumed) _rescheduleSoon();
  }

  void _rescheduleSoon() =>
      unawaited(ref.read(reminderServiceProvider).reschedule());

  @override
  Widget build(BuildContext context) {
    ref.listen(personsProvider, (_, _) => _rescheduleSoon());
    ref.listen(completionsProvider, (_, _) => _rescheduleSoon());
    ref.listen(reminderPreferencesProvider, (_, _) => _rescheduleSoon());
    return widget.child;
  }
}
