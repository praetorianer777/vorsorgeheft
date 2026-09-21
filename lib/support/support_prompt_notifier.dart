import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'support_prompt.dart';

/// Whether the person has dismissed the support prompt, read from the
/// device-local settings. Unknown until the read completes, which is what
/// keeps the prompt off a first launch's very first frame.
class SupportPromptDismissed extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final stored = await ref
        .read(databaseProvider)
        .settingValue(supportPromptDismissedKey);
    return stored == 'true';
  }

  /// Once. There is no way back, because a prompt that can come back is not
  /// a one-time prompt.
  Future<void> dismiss() async {
    state = const AsyncValue.data(true);
    await ref
        .read(databaseProvider)
        .putSetting(supportPromptDismissedKey, 'true');
  }
}

final supportPromptDismissedProvider =
    AsyncNotifierProvider<SupportPromptDismissed, bool>(
      SupportPromptDismissed.new,
    );

final supportPromptDueProvider = Provider<bool>((ref) {
  final dismissed = ref.watch(supportPromptDismissedProvider).value;
  if (dismissed == null) return false;
  final completions = ref.watch(completionsProvider).value ?? const [];
  return supportPromptDue(
    completed: completions.where((c) => !c.skipped).length,
    dismissed: dismissed,
  );
});
