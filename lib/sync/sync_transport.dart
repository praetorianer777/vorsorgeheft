import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// Thrown when a peer cannot be found or connected to. On the LAN that is
/// most often mDNS not getting through, which is why the UI answers it by
/// asking for an address instead of giving up.
class PeerUnreachableException implements Exception {
  const PeerUnreachableException(this.nodeId, [this.reason]);

  final String nodeId;
  final String? reason;

  @override
  String toString() =>
      'PeerUnreachableException($nodeId${reason == null ? '' : ': $reason'})';
}

/// One open connection, carrying whole frames in both directions.
///
/// Frames rather than bytes, so the protocol never has to know whether the
/// medium below it is a socket that splits writes or a queue that does not.
abstract class SyncChannel {
  Future<void> send(Uint8List frame);

  /// The next frame, or null once the other side has closed.
  Future<Uint8List?> receive();

  Future<void> close();
}

/// How a sync engine reaches the other phone.
///
/// The app uses [LanTransport]; the tests use [LoopbackTransport], which is
/// the same interface over in-memory queues and nothing else.
abstract class SyncTransport {
  /// Starts accepting connections as [nodeId]. Every incoming connection is
  /// handed to [onConnection] and closed when that returns.
  Future<void> listen(
    String nodeId,
    Future<void> Function(SyncChannel channel) onConnection,
  );

  Future<void> stop();

  /// Opens a channel to the peer [nodeId], found through discovery or, when
  /// discovery is unavailable, at [address].
  Future<SyncChannel> connect(String nodeId, {String? address});
}

/// The wire every [LoopbackTransport] of one test is plugged into.
class LoopbackNetwork {
  final _listeners = <String, Future<void> Function(SyncChannel)>{};

  bool isListening(String nodeId) => _listeners.containsKey(nodeId);
}

class LoopbackTransport implements SyncTransport {
  LoopbackTransport(this._network);

  final LoopbackNetwork _network;
  String? _nodeId;

  @override
  Future<void> listen(
    String nodeId,
    Future<void> Function(SyncChannel channel) onConnection,
  ) async {
    _nodeId = nodeId;
    _network._listeners[nodeId] = onConnection;
  }

  @override
  Future<void> stop() async {
    if (_nodeId != null) _network._listeners.remove(_nodeId);
  }

  @override
  Future<SyncChannel> connect(String nodeId, {String? address}) async {
    final handler = _network._listeners[nodeId];
    if (handler == null) throw PeerUnreachableException(nodeId);
    final (near, far) = LoopbackChannel.pair();
    unawaited(handler(far).whenComplete(far.close));
    return near;
  }
}

/// One end of an in-memory connection.
class LoopbackChannel implements SyncChannel {
  LoopbackChannel._();

  static (LoopbackChannel, LoopbackChannel) pair() {
    final a = LoopbackChannel._();
    final b = LoopbackChannel._();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  late final LoopbackChannel _peer;
  final _inbox = Queue<Uint8List?>();
  Completer<void>? _waiting;
  var _closed = false;

  @override
  Future<void> send(Uint8List frame) async {
    if (_closed) throw StateError('channel is closed');
    _peer._deliver(frame);
  }

  @override
  Future<Uint8List?> receive() async {
    while (_inbox.isEmpty) {
      if (_closed) return null;
      _waiting = Completer<void>();
      await _waiting!.future;
    }
    return _inbox.removeFirst();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _wake();
    _peer._deliver(null);
  }

  void _deliver(Uint8List? frame) {
    if (frame == null) {
      _closed = true;
    } else {
      _inbox.add(frame);
    }
    _wake();
  }

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }
}
