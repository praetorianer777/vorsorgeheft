import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app tells people their data stays on the device. Android backs up an
/// app's private directory to the owner's Google account unless it is told
/// not to, and that default is invisible: it shows up only when someone sets
/// up a new phone and finds the whole family already there. These files are
/// what prevents it, so they are checked here rather than trusted.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('the manifest points at both sets of backup rules', () {
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('nothing is allowed into a cloud backup on Android 12 and higher', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(
      rules.split('<cloud-backup>').last.split('</cloud-backup>').first,
      contains('<exclude domain="root" path="." />'),
    );
    expect(rules, isNot(contains('<include')));
    // Device transfer stays at its default, which copies everything: moving
    // to a new phone directly is the one path that may carry the data.
    expect(rules, isNot(contains('<device-transfer')));
  });

  test('nothing is backed up at all on Android 11 and lower', () {
    final rules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ]) {
      expect(rules, contains('<exclude domain="$domain" path="." />'));
    }
    expect(rules, isNot(contains('<include')));
  });

  test('iOS keeps the database out of the iCloud backup', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('isExcludedFromBackup = true'));
    expect(delegate, contains('.applicationSupportDirectory'));
  });
}
