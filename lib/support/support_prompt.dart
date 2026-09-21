/// Where the support link points. It lives in settings permanently; the
/// one-time prompt is only a shortcut to it.
const supportUrl = 'https://github.com/sponsors/praetorianer777';

/// Device-local on purpose. Replicated, the other parent would either never
/// see the prompt or see it a second time after dismissing it.
const supportPromptDismissedKey = 'support.prompt.dismissed';

/// The prompt appears after this many recorded appointments, and never on a
/// first launch: by then the app has done something for the person asking.
const supportPromptThreshold = 3;

/// Whether the one-time support prompt should be on screen right now.
///
/// [completed] counts appointments recorded as done, not skipped: the prompt
/// says the app has reminded the person about appointments, and a skip is a
/// decision not to have one.
bool supportPromptDue({required int completed, required bool dismissed}) =>
    !dismissed && completed >= supportPromptThreshold;
