import 'package:device_info_plus/device_info_plus.dart' as plugin;
import 'package:flutter/foundation.dart';

/// What this phone is called before anyone names it.
///
/// Behind an interface because the platform answer comes over a channel no
/// test binding has, and a spec pairing two phones needs each launch to be a
/// different model.
abstract class DeviceInfo {
  /// The marketing name of the device, such as "Pixel 8" or "iPhone 15", or
  /// null where the platform has none to offer.
  Future<String?> model();
}

class PlatformDeviceInfo implements DeviceInfo {
  const PlatformDeviceInfo();

  @override
  Future<String?> model() async {
    final info = plugin.DeviceInfoPlugin();
    try {
      final name = switch (defaultTargetPlatform) {
        TargetPlatform.android => (await info.androidInfo).model,
        TargetPlatform.iOS => (await info.iosInfo).modelName,
        _ => null,
      }?.trim();
      return name == null || name.isEmpty ? null : name;
    } on Object {
      // A phone that cannot say what it is still has to be able to pair.
      return null;
    }
  }
}

/// Answers with a fixed model, or with nothing, so a test can decide which.
class FixedDeviceInfo implements DeviceInfo {
  const FixedDeviceInfo(this._model);

  final String? _model;

  @override
  Future<String?> model() async => _model;
}
