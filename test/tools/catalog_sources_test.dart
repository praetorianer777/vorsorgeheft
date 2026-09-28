import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/catalogs.dart';

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
      expect(
        entry['covers'],
        isA<List<Object?>>().having((c) => c, 'covers', isNotEmpty),
        reason: '$id',
      );
    }
  });

  test('ids and urls are unique', () {
    final ids = sources.map((s) => (s as Map)['id']).toList();
    final urls = sources.map((s) => (s as Map)['url']).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(urls.toSet(), hasLength(urls.length));
  });

  /// The catalogs cite the guideline by its landing page, because that is
  /// where a reader should start; the watch fetches the consolidated PDF,
  /// because that is where the text is. The two therefore never match by url,
  /// and until "covers" said so, a cited document could go unwatched without
  /// anything noticing.
  test('every source a catalog cites is watched by some document', () {
    final watched = {
      for (final entry in sources.cast<Map<String, Object?>>())
        ...(entry['covers']! as List).cast<String>(),
    };
    final cited = shippedCatalogs().sources.map((s) => s.id).toSet();
    expect(cited.difference(watched), isEmpty, reason: 'cited but unwatched');
    expect(watched.difference(cited), isEmpty, reason: 'watched for nothing');
  });

  test('no two entries claim the same catalog source', () {
    final claimed = [
      for (final entry in sources.cast<Map<String, Object?>>())
        ...(entry['covers']! as List).cast<String>(),
    ];
    expect(claimed.toSet(), hasLength(claimed.length));
  });
}
