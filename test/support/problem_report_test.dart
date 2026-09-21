import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/support/problem_report.dart';

void main() {
  final url = problemReportUrl(
    appVersion: '0.1.0',
    os: 'android',
    osVersion: '14',
    locale: 'de',
  );

  test('the report opens the new-issue form of the repository', () {
    expect(url.scheme, 'https');
    expect(url.host, 'github.com');
    expect(url.path, '/praetorianer777/vorsorgereminder/issues/new');
  });

  test('title and body carry version, OS and language', () {
    expect(url.queryParameters['title'], 'Problem in 0.1.0 on android');
    final body = url.queryParameters['body']!;
    expect(body, contains('**App version:** 0.1.0'));
    expect(body, contains('**OS:** android 14'));
    expect(body, contains('**Language:** de'));
    expect(body, endsWith(problemReportPlaceholder));
  });

  test('nothing else travels with it', () {
    expect(url.queryParameters.keys, unorderedEquals(['title', 'body']));
  });
}
