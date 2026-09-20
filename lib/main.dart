import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/database_provider.dart';
import 'sync/replicated_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await openAppDatabase();
  final store = await ReplicatedStore.open(database);
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        storeProvider.overrideWithValue(store),
      ],
      child: const VorsorgereminderApp(),
    ),
  );
}
