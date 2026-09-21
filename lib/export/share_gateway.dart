import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Hands a finished file to the platform's share sheet.
///
/// Behind an interface so a test can assert on what would have been shared;
/// there is no share sheet under a widget test, and what matters there is the
/// file, not the chooser.
abstract class ShareGateway {
  Future<void> shareFile(
    File file, {
    required String subject,
    String mimeType = 'text/calendar',
  });
}

class PlatformShareGateway implements ShareGateway {
  const PlatformShareGateway();

  @override
  Future<void> shareFile(
    File file, {
    required String subject,
    String mimeType = 'text/calendar',
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        title: subject,
      ),
    );
  }
}
