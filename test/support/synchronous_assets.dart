import 'dart:io';

import 'package:flutter/services.dart';

/// Reads an asset straight off disk, completing before it is awaited.
///
/// A widget test runs on a fake clock, and a real asset read completes on the
/// real event loop, which pumping frames never advances.
///
/// Deliberately not a CachingAssetBundle: a cached Future is created inside
/// one test's fake-async zone and awaited inside the next one's, where it
/// never completes. Re-reading a small JSON file per test costs nothing.
class SynchronousAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();
}
