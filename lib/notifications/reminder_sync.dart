import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../ui/occurrence_detail_screen.dart';
import '../ui/timeline_screen.dart';
import 'notification_gateway.dart';
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
      final granted = await ref
          .read(reminderServiceProvider)
          .start(onHandled: _show);
      if (mounted) {
        ref.read(notificationPermissionProvider.notifier).set(granted: granted);
      }
    });
  }

  /// What the person sees after using a notification: the appointment it was
  /// about, or a line saying what was recorded. The work itself is already
  /// done by the time this runs.
  void _show(ReminderAction action) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (action.kind) {
      case ReminderActionKind.open:
        Navigator.of(context)
          ..popUntil((route) => route.isFirst)
          ..push(
            MaterialPageRoute<void>(
              builder: (_) => TimelineScreen(personId: action.payload.personId),
            ),
          )
          ..push(
            MaterialPageRoute<void>(
              builder: (_) => OccurrenceDetailScreen(
                personId: action.payload.personId,
                occurrenceKey: action.payload.occurrenceKey,
              ),
            ),
          );
      case ReminderActionKind.done:
        _say(l10n.reminderRecorded);
      case ReminderActionKind.later:
        _say(l10n.reminderPutOff);
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

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
