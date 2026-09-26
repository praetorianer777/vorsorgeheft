import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The mDNS answers a phone gives while it is listening for the other one.
///
/// The multicast_dns package only looks things up; it has no responder, and
/// the alternatives are platform plugins. Answering the three queries a
/// lookup makes - PTR for the service, SRV for the instance, A for the host -
/// is small enough to do here, and it means discovery works without a second
/// native dependency. It is also a stretch of hand-written bytes where a
/// wrong one means the other phone is never found and nothing fails loudly,
/// which is why it lives apart from the socket that carries it.
class MdnsAnnouncement {
  const MdnsAnnouncement({
    required this.instance,
    required this.port,
    required this.addresses,
  });

  static const serviceType = '_vorsorgereminder._tcp.local';

  static const typeA = 1;
  static const typePtr = 12;
  static const typeTxt = 16;
  static const typeSrv = 33;
  static const typeAny = 255;

  /// The node id of the phone that is listening.
  final String instance;
  final int port;
  final List<InternetAddress> addresses;

  String get instanceName => '$instance.$serviceType';
  String get hostName => '$instance.local';

  /// Whether [packet] is a question this phone should answer.
  bool answers(Uint8List packet) {
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
        typePtr => asked == serviceType,
        typeSrv || typeTxt => asked == instanceName.toLowerCase(),
        typeA => asked == hostName.toLowerCase(),
        typeAny =>
          asked == serviceType ||
              asked == instanceName.toLowerCase() ||
              asked == hostName.toLowerCase(),
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

  Uint8List response() {
    final out = BytesBuilder();
    out.add(
      (ByteData(12)
            ..setUint16(2, 0x8400)
            ..setUint16(6, 3 + addresses.length))
          .buffer
          .asUint8List(),
    );
    _record(out, serviceType, typePtr, 0x0001, _name(instanceName));
    _record(
      out,
      instanceName,
      typeSrv,
      0x8001,
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        port >> 8,
        port & 0xFF,
        ..._name(hostName),
      ]),
    );
    final txt = utf8.encode('node=$instance');
    _record(
      out,
      instanceName,
      typeTxt,
      0x8001,
      Uint8List.fromList([txt.length, ...txt]),
    );
    for (final address in addresses) {
      _record(
        out,
        hostName,
        typeA,
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
