import 'dart:io';

import 'package:vorsorgereminder/export/share_gateway.dart';

/// A share sheet that keeps the file instead of handing it to a chooser.
///
/// There is no share sheet under a test binding, and what a spec has to assert
/// is what was written, not which app the person picked.
class RecordingShareGateway implements ShareGateway {
  final List<(File, String)> shared = [];

  File get lastFile => shared.last.$1;
  String get lastSubject => shared.last.$2;
  String get lastContent => lastFile.readAsStringSync();

  @override
  Future<void> shareFile(
    File file, {
    required String subject,
    String mimeType = 'text/calendar',
  }) async => shared.add((file, subject));
}
