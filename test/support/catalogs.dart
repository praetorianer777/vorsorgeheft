import 'dart:io';

import 'package:vorsorgereminder/data/catalog_repository.dart';
import 'package:vorsorgereminder/domain/catalog.dart';

/// The catalogs that actually ship, read from disk.
///
/// Tests that need appointments use the real ones rather than a fixture, so a
/// rule that changes shape is caught here rather than on a device.
Catalog childrenCatalog() => catalogNamed('children');

Catalog catalogNamed(String id) =>
    Catalog.parse(File('assets/catalogs/$id.json').readAsStringSync());

/// Every shipped catalog, in the order the app loads them.
CatalogSet shippedCatalogs() => CatalogSet([
  for (final path in CatalogRepository.assetPaths)
    Catalog.parse(File(path).readAsStringSync()),
]);
