import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// Opens the on-device database.
///
/// Everything this app knows lives in this one file and never leaves the
/// device; there is no account and no server to fall back to, so the path is
/// the application support directory rather than a cache.
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'vorsorgereminder.sqlite'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}

/// An in-memory database, for tests and for the seeded app used by the
/// integration suite.
AppDatabase openInMemoryDatabase() => AppDatabase(NativeDatabase.memory());
