import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/sync/peer_addresses.dart';

/// With mobile data left on, a phone has a cellular address next to its
/// Wi-Fi one. Whichever comes first is the one the other phone tries first,
/// and a cellular one there used to be the whole attempt.
void main() {
  final wifi = InternetAddress('192.168.1.20');
  final cellular = InternetAddress('10.71.4.9');
  final vpn = InternetAddress('10.8.0.2');

  group('own', () {
    test(
      'Wi-Fi comes before cellular and tunnels, whatever the OS lists first',
      () {
        expect(
          PeerAddresses.own([
            ('rmnet_data0', cellular),
            ('tun0', vpn),
            ('wlan0', wifi),
          ]),
          [wifi, cellular, vpn],
        );
      },
    );

    test('iOS and desktop interface names count as LAN too', () {
      final en0 = InternetAddress('192.168.1.30');
      final eth0 = InternetAddress('192.168.1.31');
      expect(
        PeerAddresses.own([
          ('pdp_ip0', cellular),
          ('en0', en0),
          ('eth0', eth0),
        ]),
        [en0, eth0, cellular],
      );
    });
  });

  group('peer', () {
    test('an address in one of our subnets is tried first', () {
      expect(
        PeerAddresses.peer(
          [cellular, wifi],
          [InternetAddress('10.200.0.1'), InternetAddress('192.168.1.40')],
        ),
        [wifi, cellular],
      );
    });

    test('nothing is dropped, and without a match the given order stays', () {
      expect(
        PeerAddresses.peer(
          [cellular, vpn, wifi],
          [InternetAddress('172.16.0.5')],
        ),
        [cellular, vpn, wifi],
      );
    });
  });
}
