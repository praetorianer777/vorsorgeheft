import 'dart:io';

/// Which of several IPv4 addresses the other phone should try first.
///
/// A phone with mobile data left on has a cellular address next to its
/// Wi-Fi one, often a VPN address as well, and only the Wi-Fi one is
/// reachable from the other phone. Nothing in an address says which kind it
/// is, so the order comes from two hints: the name of the interface it sits
/// on, on the phone that owns it, and whether it shares a subnet with one of
/// our own, on the phone that reads it.
abstract final class PeerAddresses {
  /// Interface name prefixes of Wi-Fi and wired networks across Android,
  /// iOS and desktop Linux. Cellular ones (`rmnet`, `ccmni`, `pdp_ip`) and
  /// tunnels (`tun`, `ipsec`) are what is left over.
  static const _lanPrefixes = ['wlan', 'swlan', 'wl', 'eth', 'en', 'ap', 'br'];

  /// This phone's addresses, the ones on a Wi-Fi or wired interface first.
  static List<InternetAddress> own(
    List<(String interface, InternetAddress address)> addresses,
  ) {
    bool lan((String, InternetAddress) entry) =>
        _lanPrefixes.any(entry.$1.toLowerCase().startsWith);
    return [
      for (final entry in addresses.where(lan)) entry.$2,
      for (final entry in addresses.where((e) => !lan(e))) entry.$2,
    ];
  }

  /// The other phone's addresses, the ones in a /24 we also have an address
  /// in first, otherwise in the order the other phone gave them.
  ///
  /// The netmask is not available from [NetworkInterface], and a home
  /// network is almost always a /24; a wider one only loses the preference,
  /// not the address.
  static List<InternetAddress> peer(
    List<InternetAddress> theirs,
    List<InternetAddress> ours,
  ) {
    String subnet(InternetAddress a) => a.rawAddress.take(3).join('.');
    final local = {for (final a in ours) subnet(a)};
    bool near(InternetAddress a) => local.contains(subnet(a));
    return [...theirs.where(near), ...theirs.where((a) => !near(a))];
  }
}
