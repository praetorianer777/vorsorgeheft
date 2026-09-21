import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'change.dart';
import 'hlc.dart';
import 'pairing.dart';
import 'replicated_store.dart';
import 'session_cipher.dart';
import 'sync_transport.dart';

/// A device this one has agreed on a key with.
class Peer {
  const Peer({
    required this.nodeId,
    required this.deviceName,
    required this.sharedKey,
    this.lastSyncHlc,
    this.lastSyncAt,
  });

  final String nodeId;
  final String deviceName;

  /// The AES-256 key both phones derived from the pairing.
  final List<int> sharedKey;

  /// The peer's high-water mark as of the last exchange: everything it had
  /// written up to here has been received, so the next exchange asks for
  /// what came after.
  final Hlc? lastSyncHlc;
  final DateTime? lastSyncAt;
}

/// Where the engine keeps its peers and its own identity.
///
/// All of it is device-local by design and must never be part of a change
/// set: the private key because it is the one secret the device has, the
/// peers because the other phone's view of who it is paired with is its own.
abstract class PeerRegistry {
  Future<List<Peer>> allPeers();
  Future<Peer?> peer(String nodeId);
  Future<void> savePeer(Peer peer);
  Future<void> removePeer(String nodeId);
  Future<void> recordSync(
    String nodeId, {
    required Hlc watermark,
    required DateTime at,
  });

  Future<List<int>?> privateKey();
  Future<void> putPrivateKey(List<int> key);
  Future<String?> deviceName();
  Future<void> putDeviceName(String name);
}

class SyncResult {
  const SyncResult({
    required this.peerNodeId,
    required this.received,
    required this.sent,
  });

  final String peerNodeId;
  final int received;
  final int sent;

  bool get nothingNew => received == 0 && sent == 0;
}

/// The other side refused because it does not know this device and is not
/// showing its pairing code right now.
class UnknownPeerException implements Exception {
  const UnknownPeerException(this.nodeId);

  final String nodeId;

  @override
  String toString() => 'UnknownPeerException($nodeId)';
}

/// The other side sent something the protocol does not allow at that point.
class SyncProtocolException implements Exception {
  const SyncProtocolException(this.message);

  final String message;

  @override
  String toString() => 'SyncProtocolException: $message';
}

/// Pairs with peers and exchanges change sets with them.
///
/// One exchange, started by whichever phone taps "sync now":
///
/// 1. Both sides say who they are, in the clear. The initiator adds its
///    public key and device name, which the responder uses only if it does
///    not know the initiator yet and is currently showing its pairing code.
/// 2. Everything after that is sealed with the pair's shared key. The
///    initiator asks for what the responder wrote after the high-water mark
///    it holds for it; the responder answers with those changes, its current
///    mark, and its own question in return; the initiator answers that.
/// 3. Each side applies what it got and records the other's mark.
///
/// A change travels only from the device that made it. With two phones that
/// is every change, and it keeps an exchange from echoing a peer's own
/// changes back at it, which is what lets a repeat sync carry nothing.
class SyncEngine {
  SyncEngine({
    required ReplicatedStore store,
    required PeerRegistry registry,
    required SyncTransport transport,
    required DateTime Function() clock,
    this.pairingWindow = const Duration(minutes: 5),
  }) : _store = store,
       _registry = registry,
       _transport = transport,
       _clock = clock;

  final ReplicatedStore _store;
  final PeerRegistry _registry;
  final SyncTransport _transport;
  final DateTime Function() _clock;

  /// How long after showing the pairing code an unknown device may pair.
  final Duration pairingWindow;

  final _completed = StreamController<SyncResult>.broadcast();
  DateTime? _pairingUntil;
  DeviceIdentity? _identity;

  String get nodeId => _store.nodeId;

  /// Every exchange that finished on this device, whichever side started it.
  Stream<SyncResult> get completed => _completed.stream;

  SyncTransport get transport => _transport;

  Future<void> start() => _transport.listen(nodeId, _serve);

  Future<void> stop() => _transport.stop();

  Future<String> deviceName() async => await _registry.deviceName() ?? 'Phone';

  Future<void> rename(String name) => _registry.putDeviceName(name);

  /// The code to show the other phone. Showing it opens the window in which
  /// a device that scanned it may connect and pair.
  ///
  /// [defaultName] becomes this device's name if none was chosen yet; the
  /// screen passes a localised one, since the name is what the other parent
  /// sees.
  Future<PairingPayload> pairingPayload({String? defaultName}) async {
    final identity = await _identityOrGenerate();
    if (defaultName != null && await _registry.deviceName() == null) {
      await _registry.putDeviceName(defaultName);
    }
    _pairingUntil = _clock().add(pairingWindow);
    return PairingPayload(
      nodeId: nodeId,
      publicKey: identity.publicKey,
      deviceName: await deviceName(),
    );
  }

  bool get acceptsPairing {
    final until = _pairingUntil;
    return until != null && _clock().isBefore(until);
  }

  /// Pairs with the device whose code was scanned.
  Future<Peer> pairWith(String scannedCode) =>
      _pair(PairingPayload.decode(scannedCode));

  Future<Peer> _pair(PairingPayload payload) async {
    if (payload.nodeId == nodeId) {
      throw const FormatException('this is the code of this very device');
    }
    final identity = await _identityOrGenerate();
    final peer = Peer(
      nodeId: payload.nodeId,
      deviceName: payload.deviceName,
      sharedKey: await identity.sharedKeyWith(
        ownNodeId: nodeId,
        peerNodeId: payload.nodeId,
        peerPublicKey: payload.publicKey,
      ),
      lastSyncHlc: (await _registry.peer(payload.nodeId))?.lastSyncHlc,
    );
    await _registry.savePeer(peer);
    return peer;
  }

  Future<SyncResult> syncWith(String peerNodeId, {String? address}) async {
    final peer = await _registry.peer(peerNodeId);
    if (peer == null) throw UnknownPeerException(peerNodeId);
    final identity = await _identityOrGenerate();
    final channel = await _transport.connect(peerNodeId, address: address);
    try {
      await _sendClear(channel, {
        'v': 1,
        'nodeId': nodeId,
        'publicKey': base64.encode(identity.publicKey),
        'deviceName': await deviceName(),
      });
      final hello = await _receiveClear(channel);
      if (hello['error'] == 'unknown-peer') {
        throw UnknownPeerException(peerNodeId);
      }
      if (hello['nodeId'] != peerNodeId) {
        throw const SyncProtocolException('connected to a different device');
      }

      final session = _Session(channel, SessionCipher(peer.sharedKey));
      await session.send({
        'type': 'pull',
        'since': peer.lastSyncHlc?.toString(),
      });
      final theirs = await session.receive('changes');
      final ours = await _delta(_sinceOf(theirs['since']));
      await session.send({
        'type': 'changes',
        'changes': [for (final c in ours.$1) c.toJson()],
        'latest': ours.$2?.toString(),
      });
      final received = await _apply(peerNodeId, theirs);
      await session.receive('done');
      return _finish(
        SyncResult(
          peerNodeId: peerNodeId,
          received: received,
          sent: ours.$1.length,
        ),
      );
    } finally {
      await channel.close();
    }
  }

  /// Answers one incoming connection. Whatever goes wrong ends the
  /// connection; the initiator sees it hang up and reports that.
  Future<void> _serve(SyncChannel channel) async {
    try {
      await _respond(channel);
    } on Exception {
      // Nothing to report on this side: the initiator is the one waiting.
    }
  }

  Future<void> _respond(SyncChannel channel) async {
    final hello = await _receiveClear(channel);
    final peerNodeId = hello['nodeId'];
    if (peerNodeId is! String) {
      throw const SyncProtocolException('hello without a node id');
    }
    var peer = await _registry.peer(peerNodeId);
    if (peer == null) {
      final key = hello['publicKey'];
      final name = hello['deviceName'];
      if (!acceptsPairing || key is! String || name is! String) {
        await _sendClear(channel, {'error': 'unknown-peer'});
        return;
      }
      peer = await _pair(
        PairingPayload(
          nodeId: peerNodeId,
          publicKey: base64.decode(key),
          deviceName: name,
        ),
      );
      _pairingUntil = null;
    }
    await _sendClear(channel, {'v': 1, 'nodeId': nodeId});

    final session = _Session(channel, SessionCipher(peer.sharedKey));
    final pull = await session.receive('pull');
    final ours = await _delta(_sinceOf(pull['since']));
    await session.send({
      'type': 'changes',
      'changes': [for (final c in ours.$1) c.toJson()],
      'latest': ours.$2?.toString(),
      'since': peer.lastSyncHlc?.toString(),
    });
    final theirs = await session.receive('changes');
    final received = await _apply(peerNodeId, theirs);
    await session.send({'type': 'done'});
    _finish(
      SyncResult(
        peerNodeId: peerNodeId,
        received: received,
        sent: ours.$1.length,
      ),
    );
  }

  Hlc _sinceOf(Object? encoded) =>
      encoded is String ? Hlc.parse(encoded) : Hlc.zero('');

  /// This device's own changes after [since], and the mark the peer should
  /// hold for it. The mark is read together with the delta rather than after
  /// the peer's changes were applied, or a local write landing in between
  /// would sort below the mark and never be sent.
  Future<(List<Change>, Hlc?)> _delta(Hlc since) async {
    final changes = await _store.changesSince(since);
    return (
      changes.where((c) => c.hlc.nodeId == nodeId).toList(),
      await _store.latest,
    );
  }

  Future<int> _apply(String peerNodeId, Map<String, Object?> message) async {
    final raw = message['changes'];
    if (raw is! List) throw const SyncProtocolException('changes missing');
    final changes = [
      for (final json in raw) Change.fromJson((json as Map).cast()),
    ];
    final applied = await _store.merge(changes);
    final latest = message['latest'];
    await _registry.recordSync(
      peerNodeId,
      watermark: latest is String ? Hlc.parse(latest) : Hlc.zero(peerNodeId),
      at: _clock(),
    );
    return applied.length;
  }

  SyncResult _finish(SyncResult result) {
    _completed.add(result);
    return result;
  }

  Future<DeviceIdentity> _identityOrGenerate() async {
    if (_identity != null) return _identity!;
    final stored = await _registry.privateKey();
    if (stored != null) {
      return _identity = await DeviceIdentity.fromPrivateKey(stored);
    }
    final generated = await DeviceIdentity.generate();
    await _registry.putPrivateKey(generated.privateKey);
    return _identity = generated;
  }

  Future<void> _sendClear(SyncChannel channel, Map<String, Object?> message) =>
      channel.send(Uint8List.fromList(utf8.encode(jsonEncode(message))));

  Future<Map<String, Object?>> _receiveClear(SyncChannel channel) async {
    final frame = await channel.receive();
    if (frame == null) throw const SyncProtocolException('peer hung up');
    return _decode(frame);
  }

  static Map<String, Object?> _decode(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const SyncProtocolException('frame is not JSON');
    }
    if (json is! Map) throw const SyncProtocolException('frame is not a map');
    return json.cast<String, Object?>();
  }
}

/// The encrypted part of an exchange.
class _Session {
  _Session(this._channel, this._cipher);

  final SyncChannel _channel;
  final SessionCipher _cipher;

  Future<void> send(Map<String, Object?> message) async =>
      _channel.send(await _cipher.seal(utf8.encode(jsonEncode(message))));

  Future<Map<String, Object?>> receive(String expectedType) async {
    final frame = await _channel.receive();
    if (frame == null) throw const SyncProtocolException('peer hung up');
    final message = SyncEngine._decode(await _cipher.open(frame));
    if (message['type'] != expectedType) {
      throw SyncProtocolException(
        'expected $expectedType, got ${message['type']}',
      );
    }
    return message;
  }
}
