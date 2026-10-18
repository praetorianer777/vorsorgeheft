import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

import 'mdns_announcement.dart';
import 'peer_addresses.dart';
import 'sync_transport.dart';

/// TCP on the local network, with the peer found through mDNS.
///
/// Discovery is best effort: emulators, guest networks and some routers drop
/// multicast, and then a lookup finds nothing rather than failing loudly. The
/// address the listener prints lets the person type it into the other phone
/// in that case, which is the path [connect] takes when it is given one.
class LanTransport implements SyncTransport {
  LanTransport({this.lookupTimeout = const Duration(seconds: 4)});

  static const serviceType = MdnsAnnouncement.serviceType;

  /// Anything larger than this is not a sync frame, and reading it would
  /// mean allocating whatever length a stray connection claims.
  static const maxFrameLength = 64 * 1024 * 1024;

  final Duration lookupTimeout;

  ServerSocket? _server;
  _MdnsResponder? _responder;

  /// `host:port` on the first non-loopback IPv4 address, Wi-Fi before
  /// cellular, or null when not listening.
  @override
  Future<String?> localAddress() async {
    final server = _server;
    if (server == null) return null;
    final addresses = await _localAddresses();
    if (addresses.isEmpty) return null;
    return '${addresses.first.address}:${server.port}';
  }

  @override
  Future<void> listen(
    String nodeId,
    Future<void> Function(SyncChannel channel) onConnection,
  ) async {
    await stop();
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen((socket) {
      final channel = _SocketChannel(socket);
      unawaited(
        onConnection(channel).catchError((_) {}).whenComplete(channel.close),
      );
    });
    try {
      _responder = await _MdnsResponder.start(
        instance: nodeId,
        port: server.port,
        addresses: _localAddresses,
      );
    } on IOException {
      // Multicast is not available here; the manual address path remains.
    } on OSError {
      // Same, reported by joinMulticast rather than by the bind.
    }
  }

  /// The port this device accepts connections on, or null when not listening.
  int? get port => _server?.port;

  @override
  Future<void> stop() async {
    _responder?.stop();
    _responder = null;
    await _server?.close();
    _server = null;
  }

  @override
  Future<SyncChannel> connect(String nodeId, {String? address}) async {
    final endpoints = address == null
        ? await _discover(nodeId)
        : [_parseAddress(nodeId, address)];
    String? reason;
    for (final (host, port) in endpoints) {
      try {
        final socket = await Socket.connect(host, port, timeout: lookupTimeout);
        return _SocketChannel(socket);
      } on SocketException catch (e) {
        reason = e.message;
      }
    }
    throw PeerUnreachableException(nodeId, reason);
  }

  (String, int) _parseAddress(String nodeId, String address) {
    final colon = address.lastIndexOf(':');
    final port = colon < 0 ? null : int.tryParse(address.substring(colon + 1));
    if (port == null) {
      throw PeerUnreachableException(nodeId, 'address must be host:port');
    }
    return (address.substring(0, colon), port);
  }

  /// Every address the peer announced, the likeliest first; empty when it
  /// was not found.
  Future<List<(String, int)>> _discover(String nodeId) async {
    final client = MDnsClient();
    try {
      await client.start();
      final instance = '$nodeId.$serviceType';
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
        timeout: lookupTimeout,
      )) {
        if (ptr.domainName != instance) continue;
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(instance),
          timeout: lookupTimeout,
        )) {
          // The responder sends its A records in the same packet as the PTR,
          // so they are in the client's cache by now and this stream closes
          // at once instead of waiting out the timeout.
          final hosts = await client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
                timeout: lookupTimeout,
              )
              .map((record) => record.address)
              .toList();
          return [
            for (final host in PeerAddresses.peer(
              hosts,
              await _localAddresses(),
            ))
              (host.address, srv.port),
          ];
        }
      }
      return const [];
    } on IOException {
      return const [];
    } on OSError {
      return const [];
    } finally {
      client.stop();
    }
  }
}

Future<List<InternetAddress>> _localAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return PeerAddresses.own([
    for (final i in interfaces)
      for (final a in i.addresses) (i.name, a),
  ]);
}

/// Length-prefixed frames over a socket.
class _SocketChannel implements SyncChannel {
  _SocketChannel(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder(copy: false);
  final _frames = <Uint8List>[];
  Completer<void>? _waiting;
  var _done = false;

  @override
  Future<void> send(Uint8List frame) async {
    final header = ByteData(4)..setUint32(0, frame.length);
    _socket.add(header.buffer.asUint8List());
    _socket.add(frame);
    await _socket.flush();
  }

  @override
  Future<Uint8List?> receive() async {
    while (_frames.isEmpty) {
      if (_done) return null;
      _waiting = Completer<void>();
      await _waiting!.future;
    }
    return _frames.removeAt(0);
  }

  @override
  Future<void> close() async {
    _done = true;
    await _subscription.cancel();
    await _socket.close();
    _socket.destroy();
    _wake();
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 4) return;
      final length = ByteData.sublistView(bytes).getUint32(0);
      if (length > LanTransport.maxFrameLength) {
        _onDone();
        return;
      }
      if (bytes.length < 4 + length) return;
      _frames.add(Uint8List.sublistView(bytes, 4, 4 + length));
      _buffer.clear();
      _buffer.add(Uint8List.sublistView(bytes, 4 + length));
      _wake();
    }
  }

  void _onDone() {
    _done = true;
    _wake();
  }

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }
}

/// Answers mDNS queries for this device's service instance.
///
/// The socket that carries [MdnsAnnouncement] onto the network.
class _MdnsResponder {
  _MdnsResponder._(this._socket, this._instance, this._port, this._addresses);

  static final _group = InternetAddress('224.0.0.251');
  static const _mdnsPort = 5353;

  static Future<_MdnsResponder> start({
    required String instance,
    required int port,
    required Future<List<InternetAddress>> Function() addresses,
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _mdnsPort,
      reuseAddress: true,
      reusePort: !Platform.isAndroid,
    );
    socket.joinMulticast(_group);
    socket.multicastHops = 255;
    final responder = _MdnsResponder._(socket, instance, port, addresses);
    socket.listen(responder._onEvent);
    unawaited(responder._announce());
    return responder;
  }

  final RawDatagramSocket _socket;
  final String _instance;
  final int _port;

  /// Read for every answer rather than once, because the phone may have
  /// joined the Wi-Fi or got a new lease since it started listening.
  final Future<List<InternetAddress>> Function() _addresses;
  var _stopped = false;

  void stop() {
    _stopped = true;
    _socket.close();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket.receive();
    if (datagram == null) return;
    if (_announcement([]).answers(datagram.data)) unawaited(_announce());
  }

  MdnsAnnouncement _announcement(List<InternetAddress> addresses) =>
      MdnsAnnouncement(instance: _instance, port: _port, addresses: addresses);

  Future<void> _announce() async {
    final response = _announcement(await _addresses()).response();
    if (_stopped) return;
    _socket.send(response, _group, _mdnsPort);
  }
}
