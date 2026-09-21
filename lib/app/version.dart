/// The version the settings screen shows.
///
/// A constant rather than a platform lookup: the version is only ever read to
/// print it, and a unit test keeps it in step with `pubspec.yaml`, which is
/// cheaper than a plugin every widget test would then have to fake.
const appVersion = '0.1.0';
