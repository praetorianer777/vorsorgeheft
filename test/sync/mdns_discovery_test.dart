import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/sync/lan_transport.dart';

/// The one part of discovery that no unit test reaches: a phone announcing
/// itself and another one finding it over multicast.
///
/// It needs a network that carries multicast to itself, which a CI runner,
/// an emulator and most guest networks do not, so it is opt-in:
///
///     MDNS_E2E=1 flutter test test/sync/mdns_discovery_test.dart
///
/// What it cannot prove is the case the app is most often blamed for - two
/// phones on a router that drops multicast - and that is exactly why the
/// address prompt exists next to it.
void main() {
  final enabled = Platform.environment['MDNS_E2E'] == '1';

  test(
    'a listening phone is found by name and the two exchange a frame',
    () async {
      final mum = LanTransport();
      final dad = LanTransport();
      addTearDown(mum.stop);
      addTearDown(dad.stop);

      final received = <List<int>>[];
      await mum.listen('mums-phone', (channel) async {
        final frame = await channel.receive();
        if (frame != null) {
          received.add(frame);
          await channel.send(Uint8List.fromList([...frame.reversed]));
        }
      });

      // No address: this is the lookup, not the fallback.
      final channel = await dad.connect('mums-phone');
      addTearDown(channel.close);
      await channel.send(Uint8List.fromList([1, 2, 3]));
      final answer = await channel.receive();

      expect(received, [
        [1, 2, 3],
      ]);
      expect(answer, [3, 2, 1]);
    },
    skip: enabled ? false : 'set MDNS_E2E=1 on a network that has multicast',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
