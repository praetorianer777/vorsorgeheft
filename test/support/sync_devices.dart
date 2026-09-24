import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/sync/device_info.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';
import 'package:vorsorgeheft/sync/sync_protocol.dart';
import 'package:vorsorgeheft/sync/sync_transport.dart';

/// A phone: its own database, store, engine and clock, on the shared wire.
class Device {
  Device._(this.name, this.db, this.store, this.engine, this._clock);

  static Future<Device> open(
    String name,
    LoopbackNetwork network, {
    String? model,
  }) async {
    final db = openInMemoryDatabase();
    final clock = _Clock(DateTime.utc(2026, 9, 20));
    final store = await ReplicatedStore.open(
      db,
      nodeId: name,
      clock: clock.read,
    );
    final engine = SyncEngine(
      store: store,
      registry: db,
      transport: LoopbackTransport(network),
      clock: clock.read,
      deviceInfo: FixedDeviceInfo(model),
    );
    await engine.start();
    return Device._(name, db, store, engine, clock);
  }

  final String name;
  final AppDatabase db;
  final ReplicatedStore store;
  final SyncEngine engine;
  final _Clock _clock;

  void advance(Duration by) => _clock.advance(by);

  Future<void> close() async {
    await engine.stop();
    await db.close();
  }
}

class _Clock {
  _Clock(this._now);

  DateTime _now;

  DateTime read() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

/// One phone shows its code, the other scans it.
Future<void> pair(Device shows, Device scans) async {
  final code = (await shows.engine.pairingPayload()).encode();
  await scans.engine.pairWith(code);
}
