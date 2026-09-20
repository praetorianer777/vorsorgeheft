import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/localized_text.dart';

/// A missing translation must fail the build rather than fall back silently at
/// runtime, where nobody notices it until a user sees English in a German app.
void main() {
  Map<String, Object?> arb(String locale) =>
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, Object?>;

  Set<String> messageKeys(Map<String, Object?> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  test('every locale the app claims to support has an ARB file', () {
    for (final locale in LocalizedText.supportedLocales) {
      expect(
        File('lib/l10n/app_$locale.arb').existsSync(),
        isTrue,
        reason: locale,
      );
    }
  });

  test('the locales carry exactly the same keys', () {
    final en = messageKeys(arb('en'));
    final de = messageKeys(arb('de'));
    expect(en.difference(de), isEmpty, reason: 'missing from German');
    expect(de.difference(en), isEmpty, reason: 'not in the English template');
  });

  test('no message is left empty', () {
    for (final locale in LocalizedText.supportedLocales) {
      final messages = arb(locale);
      for (final key in messageKeys(messages)) {
        if (key == '@@locale') continue;
        expect(
          (messages[key]! as String).trim(),
          isNotEmpty,
          reason: '$locale/$key',
        );
      }
    }
  });

  test('placeholders match across locales', () {
    final placeholder = RegExp(r'\{(\w+)');
    final en = arb('en');
    final de = arb('de');
    for (final key in messageKeys(en)) {
      if (key == '@@locale') continue;
      expect(
        placeholder
            .allMatches(de[key]! as String)
            .map((m) => m.group(1))
            .toSet(),
        placeholder
            .allMatches(en[key]! as String)
            .map((m) => m.group(1))
            .toSet(),
        reason: key,
      );
    }
  });
}
