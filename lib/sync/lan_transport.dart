import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

import 'sync_transport.dart';

/// TCP on the local network, with the peer found through mDNS.
///
/// Discovery is best effort: emulators, guest networks and some routers drop
/// multicast, and then a lookup finds nothing rather than failing loudly. The
/// address the listener prints lets the person type it into the other phone
/// in that case, which is the path [connect] takes when it is given one.
class LanTransport implements SyncTransport {
  LanTransport({this.lookupTimeout = const Duration(seconds: 4)});

  static const serviceType = '_vorsorgereminder._tcp.local';

  /// Anything larger than this is not a sync frame, and reading it would
  /// mean allocating whatever length a stray connection claims.
  static const maxFrameLength = 64 * 1024 * 1024;

  final Duration lookupTimeout;

  ServerSocket? _server;
  _MdnsResponder? _responder;

  /// `host:port` of the first non-loopback IPv4 interface, or null when not
  /// listening.
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
        addresses: await _localAddresses(),
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
    final endpoint = address == null
        ? await _discover(nodeId)
        : _parseAddress(nodeId, address);
    if (endpoint == null) throw PeerUnreachableException(nodeId);
    try {
      final socket = await Socket.connect(
        endpoint.$1,
        endpoint.$2,
        timeout: lookupTimeout,
      );
      return _SocketChannel(socket);
    } on SocketException catch (e) {
      throw PeerUnreachableException(nodeId, e.message);
    }
  }

  (String, int)? _parseAddress(String nodeId, String address) {
    final colon = address.lastIndexOf(':');
    final port = colon < 0 ? null : int.tryParse(address.substring(colon + 1));
    if (port == null) {
      throw PeerUnreachableException(nodeId, 'address must be host:port');
    }
    return (address.substring(0, colon), port);
  }

  Future<(String, int)?> _discover(String nodeId) async {
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
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: lookupTimeout,
          )) {
            return (ip.address.address, srv.port);
          }
        }
      }
      return null;
    } on IOException {
      return null;
    } on OSError {
      return null;
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
  return [for (final i in interfaces) ...i.addresses];
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
/// The multicast_dns package only looks things up; it has no responder, and
/// the alternatives are platform plugins. Answering the three queries a
/// lookup makes - PTR for the service, SRV for the instance, A for the host -
/// is small enough to do here, and it means discovery works without a
/// second native dependency.
class _MdnsResponder {
  _MdnsResponder._(this._socket, this._instance, this._port, this._addresses);

  static final _group = InternetAddress('224.0.0.251');
  static const _mdnsPort = 5353;
  static const _typeA = 1;
  static const _typePtr = 12;
  static const _typeTxt = 16;
  static const _typeSrv = 33;
  static const _typeAny = 255;

  static Future<_MdnsResponder> start({
    required String instance,
    required int port,
    required List<InternetAddress> addresses,
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
    responder._announce();
    return responder;
  }

  final RawDatagramSocket _socket;
  final String _instance;
  final int _port;
  final List<InternetAddress> _addresses;

  String get _instanceName => '$_instance.${LanTransport.serviceType}';
  String get _hostName => '$_instance.local';

  void stop() => _socket.close();

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket.receive();
    if (datagram == null) return;
    if (_asksForUs(datagram.data)) _announce();
  }

  void _announce() => _socket.send(_response(), _group, _mdnsPort);

  bool _asksForUs(Uint8List packet) {
    if (packet.length < 12) return false;
    final data = ByteData.sublistView(packet);
    if (data.getUint16(2) & 0x8000 != 0) return false;
    final questions = data.getUint16(4);
    var offset = 12;
    for (var i = 0; i < questions; i++) {
      final name = _readName(packet, offset);
      if (name == null) return false;
      offset = name.$2;
      if (offset + 4 > packet.length) return false;
      final type = data.getUint16(offset);
      offset += 4;
      final asked = name.$1.toLowerCase();
      final matches = switch (type) {
        _typePtr => asked == LanTransport.serviceType,
        _typeSrv || _typeTxt => asked == _instanceName.toLowerCase(),
        _typeA => asked == _hostName.toLowerCase(),
        _typeAny =>
          asked == LanTransport.serviceType ||
              asked == _instanceName.toLowerCase() ||
              asked == _hostName.toLowerCase(),
        _ => false,
      };
      if (matches) return true;
    }
    return false;
  }

  /// A name and the offset after it, following compression pointers as
  /// RFC 1035 lays them out; null when the packet is malformed.
  (String, int)? _readName(Uint8List packet, int offset) {
    final labels = <String>[];
    int? end;
    var hops = 0;
    while (true) {
      if (offset >= packet.length || hops++ > 64) return null;
      final length = packet[offset];
      if (length == 0) {
        end ??= offset + 1;
        return (labels.join('.'), end);
      }
      if (length & 0xC0 == 0xC0) {
        if (offset + 1 >= packet.length) return null;
        end ??= offset + 2;
        offset = ((length & 0x3F) << 8) | packet[offset + 1];
        continue;
      }
      if (offset + 1 + length > packet.length) return null;
      labels.add(
        utf8.decode(
          packet.sublist(offset + 1, offset + 1 + length),
          allowMalformed: true,
        ),
      );
      offset += 1 + length;
    }
  }

  Uint8List _response() {
    final out = BytesBuilder();
    out.add(
      (ByteData(12)
            ..setUint16(2, 0x8400)
            ..setUint16(6, 3 + _addresses.length))
          .buffer
          .asUint8List(),
    );
    _record(
      out,
      LanTransport.serviceType,
      _typePtr,
      0x0001,
      _name(_instanceName),
    );
    _record(
      out,
      _instanceName,
      _typeSrv,
      0x8001,
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        _port >> 8,
        _port & 0xFF,
        ..._name(_hostName),
      ]),
    );
    final txt = utf8.encode('node=$_instance');
    _record(
      out,
      _instanceName,
      _typeTxt,
      0x8001,
      Uint8List.fromList([txt.length, ...txt]),
    );
    for (final address in _addresses) {
      _record(
        out,
        _hostName,
        _typeA,
        0x8001,
        Uint8List.fromList(address.rawAddress),
      );
    }
    return out.toBytes();
  }

  void _record(
    BytesBuilder out,
    String name,
    int type,
    int rrClass,
    Uint8List data,
  ) {
    out.add(_name(name));
    out.add(
      (ByteData(10)
            ..setUint16(0, type)
            ..setUint16(2, rrClass)
            ..setUint32(4, 120)
            ..setUint16(8, data.length))
          .buffer
          .asUint8List(),
    );
    out.add(data);
  }

  Uint8List _name(String name) {
    final out = BytesBuilder();
    for (final label in name.split('.')) {
      final bytes = utf8.encode(label);
      out.addByte(bytes.length);
      out.add(bytes);
    }
    out.addByte(0);
    return out.toBytes();
  }
}
