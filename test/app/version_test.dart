import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/app/version.dart';

void main() {
  test('the version in settings is the one the app is built with', () {
    final declared = RegExp(
      r'^version:\s*([0-9.]+)\+',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());

    expect(declared?.group(1), appVersion);
  });
}
