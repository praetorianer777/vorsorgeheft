import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// The decoder the other phone reads these answers with. Importing it here is
// what makes the assertions about interoperability rather than about our own
// reading of our own bytes.
import 'package:multicast_dns/multicast_dns.dart';
// The decoder itself is not exported; the record types above are.
// ignore: implementation_imports
import 'package:multicast_dns/src/packet.dart' show decodeMDnsResponse;
import 'package:vorsorgeheft/sync/mdns_announcement.dart';

/// The app writes its own mDNS answers, because the package it uses only
/// looks things up. A wrong byte here means the other phone is never found
/// on the network, and nothing fails loudly: the lookup simply comes back
/// empty and the person is asked for an address instead.
void main() {
  final announcement = MdnsAnnouncement(
    instance: 'mums-phone',
    port: 4321,
    addresses: [InternetAddress('192.168.1.20')],
  );

  Uint8List name(String value) {
    final out = BytesBuilder();
    for (final label in value.split('.')) {
      out.addByte(label.length);
      out.add(utf8.encode(label));
    }
    out.addByte(0);
    return out.toBytes();
  }

  /// One question, the way a lookup asks it.
  Uint8List query(String asked, int type, {int flags = 0, int questions = 1}) {
    final header = ByteData(12)
      ..setUint16(2, flags)
      ..setUint16(4, questions);
    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...name(asked),
      type >> 8,
      type & 0xFF,
      0,
      1,
    ]);
  }

  group('which questions are ours', () {
    test('the three a lookup asks are answered', () {
      expect(
        announcement.answers(
          query(MdnsAnnouncement.serviceType, MdnsAnnouncement.typePtr),
        ),
        isTrue,
      );
      expect(
        announcement.answers(
          query(announcement.instanceName, MdnsAnnouncement.typeSrv),
        ),
        isTrue,
      );
      expect(
        announcement.answers(
          query(announcement.hostName, MdnsAnnouncement.typeA),
        ),
        isTrue,
      );
    });

    test('a question about anything is answered for all three names', () {
      for (final asked in [
        MdnsAnnouncement.serviceType,
        announcement.instanceName,
        announcement.hostName,
      ]) {
        expect(
          announcement.answers(query(asked, MdnsAnnouncement.typeAny)),
          isTrue,
          reason: asked,
        );
      }
    });

    test('the name is matched without regard to case', () {
      expect(
        announcement.answers(
          query(
            MdnsAnnouncement.serviceType.toUpperCase(),
            MdnsAnnouncement.typePtr,
          ),
        ),
        isTrue,
      );
    });

    test('another service on the same network is not ours to answer', () {
      expect(
        announcement.answers(
          query('_airplay._tcp.local', MdnsAnnouncement.typePtr),
        ),
        isFalse,
      );
      expect(
        announcement.answers(
          query(
            'dads-phone.${MdnsAnnouncement.serviceType}',
            MdnsAnnouncement.typeSrv,
          ),
        ),
        isFalse,
      );
    });

    test('our own name asked about with the wrong type is not answered', () {
      expect(
        announcement.answers(
          query(announcement.instanceName, MdnsAnnouncement.typeA),
        ),
        isFalse,
      );
    });

    test('an answer from somebody else is not a question', () {
      // Every phone on the network sees every announcement, and answering
      // one would be an endless exchange between two of ours.
      expect(
        announcement.answers(
          query(
            MdnsAnnouncement.serviceType,
            MdnsAnnouncement.typePtr,
            flags: 0x8400,
          ),
        ),
        isFalse,
      );
    });
  });

  group('a packet that is not a packet', () {
    test('an empty or truncated one is refused', () {
      expect(announcement.answers(Uint8List(0)), isFalse);
      expect(announcement.answers(Uint8List(11)), isFalse);
      final full = query(
        MdnsAnnouncement.serviceType,
        MdnsAnnouncement.typePtr,
      );
      expect(
        announcement.answers(full.sublist(0, full.length - 3)),
        isFalse,
        reason: 'the type is cut off',
      );
    });

    test('a name that never ends is refused', () {
      final header = ByteData(12)..setUint16(4, 1);
      expect(
        announcement.answers(
          Uint8List.fromList([...header.buffer.asUint8List(), 5, 1, 2, 3]),
        ),
        isFalse,
      );
    });

    test('a compression pointer that loops is refused', () {
      // 0xC0 0x0C points back at the start of the question section, which is
      // the pointer itself: following it forever is the trap this guards.
      final header = ByteData(12)..setUint16(4, 1);
      expect(
        announcement.answers(
          Uint8List.fromList([...header.buffer.asUint8List(), 0xC0, 0x0C]),
        ),
        isFalse,
      );
    });

    test('a question count larger than the packet is refused', () {
      // The first question is somebody else's, and the three the header
      // promises after it are not there at all.
      expect(
        announcement.answers(
          query('_airplay._tcp.local', MdnsAnnouncement.typePtr, questions: 4),
        ),
        isFalse,
      );
    });
  });

  group('what the answer says', () {
    final records = decodeMDnsResponse(announcement.response())!;

    test('it is a response, and it carries every record a lookup needs', () {
      expect(
        records.whereType<PtrResourceRecord>().single.domainName,
        announcement.instanceName,
      );
      final srv = records.whereType<SrvResourceRecord>().single;
      expect(srv.name, announcement.instanceName);
      expect(srv.port, 4321);
      expect(srv.target, announcement.hostName);
      final ip = records.whereType<IPAddressResourceRecord>().single;
      expect(ip.name, announcement.hostName);
      expect(ip.address.address, '192.168.1.20');
      expect(
        records.whereType<TxtResourceRecord>().single.text,
        contains('node=mums-phone'),
      );
    });

    test('every address the phone has is offered', () {
      final two = MdnsAnnouncement(
        instance: 'dads-phone',
        port: 5000,
        addresses: [
          InternetAddress('10.0.0.5'),
          InternetAddress('192.168.178.31'),
        ],
      );
      final answered = decodeMDnsResponse(
        two.response(),
      )!.whereType<IPAddressResourceRecord>().map((r) => r.address.address);
      expect(answered, ['10.0.0.5', '192.168.178.31']);
    });
  });
}
