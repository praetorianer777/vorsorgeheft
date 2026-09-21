import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../sync/sync_protocol.dart';

/// Keeps this device reachable for the other phone while the app is open.
///
/// Listening starts here rather than on the sync screen, so a person who
/// taps "sync now" finds the other phone reachable without the other parent
/// having to open the same screen at the same moment.
class SyncListener extends ConsumerStatefulWidget {
  const SyncListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncListener> createState() => _SyncListenerState();
}

class _SyncListenerState extends ConsumerState<SyncListener> {
  late final SyncEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = ref.read(syncEngineProvider);
    unawaited(_engine.start());
  }

  @override
  void dispose() {
    unawaited(_engine.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
