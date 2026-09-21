import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../export/share_gateway.dart';
import 'bundle.dart';
import 'hlc.dart';
import 'replicated_store.dart';

/// Lets the person choose a bundle file to import.
///
/// Behind an interface for the same reason as the share sheet: there is no
/// file chooser under a test binding, and what a spec has to control is which
/// bytes come back.
abstract class BundlePicker {
  /// The chosen file's bytes, or null when the person backed out.
  Future<List<int>?> pick();
}

class PlatformBundlePicker implements BundlePicker {
  const PlatformBundlePicker();

  @override
  Future<List<int>?> pick() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return null;
    return files.single.readAsBytes();
  }
}

/// Writes the change set to a password-sealed file and reads one back in.
class BundleService {
  BundleService({
    required ReplicatedStore store,
    required ShareGateway share,
    required BundlePicker picker,
    Future<Directory> Function()? directory,
  }) : _store = store,
       _share = share,
       _picker = picker,
       _directory = directory ?? getTemporaryDirectory;

  final ReplicatedStore _store;
  final ShareGateway _share;
  final BundlePicker _picker;
  final Future<Directory> Function() _directory;

  /// Seals everything this device knows and hands the file to the share
  /// sheet. Everything rather than a delta: a file has no peer to hold a mark
  /// for, and applying changes twice is a no-op anyway.
  Future<File> export({
    required String password,
    required String subject,
  }) async {
    final changes = await _store.changesSince(Hlc.zero(''));
    final bytes = await SyncBundle.seal(
      nodeId: _store.nodeId,
      changes: changes,
      password: password,
    );
    final file = File(
      p.join(
        (await _directory()).path,
        SyncBundle.fileName(await _store.latest),
      ),
    );
    await file.writeAsBytes(bytes);
    await _share.shareFile(
      file,
      subject: subject,
      mimeType: 'application/octet-stream',
    );
    return file;
  }

  /// Opens the chosen file under [password] and applies what it carries.
  /// Null when no file was chosen.
  Future<MergeResult?> import({required String password}) async {
    final bytes = await _picker.pick();
    if (bytes == null) return null;
    final contents = await SyncBundle.open(bytes, password);
    return _store.merge(contents.changes, from: contents.nodeId);
  }
}
