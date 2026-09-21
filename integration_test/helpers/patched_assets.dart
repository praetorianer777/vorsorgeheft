import 'dart:convert';

import 'package:flutter/services.dart';

/// The shipped assets, with one catalog rewritten in flight.
///
/// A spec about an app update cannot ship a second edition of a catalog, so it
/// plays the update by handing the app the real catalog with a new version
/// and a new note. Everything else is served untouched from [base].
class PatchedAssetBundle extends AssetBundle {
  PatchedAssetBundle(this.base, {required this.path, required this.patch});

  final AssetBundle base;
  final String path;
  final Map<String, Object?> Function(Map<String, Object?> catalog) patch;

  @override
  Future<ByteData> load(String key) => base.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final source = await base.loadString(key, cache: cache);
    if (key != path) return source;
    final json = (jsonDecode(source) as Map).cast<String, Object?>();
    return jsonEncode(patch(json));
  }
}
