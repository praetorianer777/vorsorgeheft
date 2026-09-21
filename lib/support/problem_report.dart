/// Where a problem report is filed. The settings tile opens this page with the
/// title and body prefilled; GitHub shows the form, the person edits and sends.
const problemReportBaseUrl =
    'https://github.com/praetorianer777/vorsorgereminder/issues/new';

/// The line the person is meant to replace with what went wrong.
const problemReportPlaceholder = '<describe what happened here>';

/// The URL of the new-issue form with everything the developer needs to
/// reproduce, and nothing more.
///
/// The app sends no telemetry, so this is the only channel a report travels
/// on: the browser shows the whole text before the person submits it, and the
/// body names only the app version, the operating system and the app
/// language. No identifiers, no logs unless the person pastes them in.
Uri problemReportUrl({
  required String appVersion,
  required String os,
  required String osVersion,
  required String locale,
}) {
  final body = [
    '**App version:** $appVersion',
    '**OS:** $os $osVersion',
    '**Language:** $locale',
    '',
    '**What happened:**',
    problemReportPlaceholder,
  ].join('\n');
  return Uri.parse(problemReportBaseUrl).replace(
    queryParameters: {'title': 'Problem in $appVersion on $os', 'body': body},
  );
}
