import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The nightly catalog watch reads this file with jq and fetches every url in
/// it. A malformed entry would not fail loudly there; it would silently stop
/// a guideline from being watched.
void main() {
  final sources =
      (jsonDecode(File('tools/catalog-sources.json').readAsStringSync())
              as Map<String, Object?>)['sources']
          as List;

  test('every entry names a https document', () {
    expect(sources, isNotEmpty);
    for (final entry in sources.cast<Map<String, Object?>>()) {
      final id = entry['id'];
      expect(id, isA<String>().having((s) => s, 'id', isNotEmpty));
      // The id becomes a file name under tools/catalog-sources.
      expect(id, matches(RegExp(r'^[a-z0-9-]+$')), reason: '$id');
      expect(entry['name'], isA<String>(), reason: '$id');
      expect(entry['url'], startsWith('https://'), reason: '$id');
    }
  });

  test('ids and urls are unique', () {
    final ids = sources.map((s) => (s as Map)['id']).toList();
    final urls = sources.map((s) => (s as Map)['url']).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(urls.toSet(), hasLength(urls.length));
  });
}
