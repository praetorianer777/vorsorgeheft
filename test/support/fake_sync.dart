import 'package:flutter/widgets.dart';
import 'package:vorsorgereminder/sync/bundle_service.dart';
import 'package:vorsorgereminder/ui/qr_scanner.dart';

/// A scanner that answers with whatever the test put in front of it.
///
/// There is no camera under a test binding, and what a spec has to control
/// is which code was read.
class FakeQrScanner implements QrScanner {
  String? nextCode;

  @override
  Future<String?> scan(BuildContext context) async {
    final code = nextCode;
    nextCode = null;
    return code;
  }
}

/// A file chooser that answers with whatever bytes the test handed it.
class FakeBundlePicker implements BundlePicker {
  List<int>? nextFile;

  @override
  Future<List<int>?> pick() async => nextFile;
}
