import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../domain/catalog.dart';

/// Loads the catalogs that ship with the app.
///
/// The list is explicit rather than discovered from the asset manifest so that
/// a catalog nobody wired up fails loudly in tests instead of silently going
/// missing from someone's timeline.
class CatalogRepository {
  const CatalogRepository({AssetBundle? bundle}) : _bundle = bundle;

  static const assetPaths = [
    'assets/catalogs/children.json',
    'assets/catalogs/vaccinations.json',
    'assets/catalogs/dental.json',
    'assets/catalogs/adults.json',
    'assets/catalogs/dogs.json',
    'assets/catalogs/cats.json',
  ];

  final AssetBundle? _bundle;

  Future<CatalogSet> load() async {
    final bundle = _bundle ?? rootBundle;
    final catalogs = <Catalog>[];
    for (final path in assetPaths) {
      catalogs.add(Catalog.parse(await bundle.loadString(path)));
    }
    return CatalogSet(catalogs);
  }
}
