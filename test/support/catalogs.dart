import 'dart:io';

import 'package:vorsorgereminder/domain/catalog.dart';

/// The catalog that actually ships, read from disk.
///
/// Tests that need appointments use the real one rather than a fixture, so a
/// rule that changes shape is caught here rather than on a device.
Catalog childrenCatalog() =>
    Catalog.parse(File('assets/catalogs/children.json').readAsStringSync());
