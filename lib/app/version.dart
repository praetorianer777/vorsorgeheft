/// The version the settings screen shows.
///
/// A constant rather than a platform lookup: the version is only ever read to
/// print it, and a unit test keeps it in step with `pubspec.yaml`, which is
/// cheaper than a plugin every widget test would then have to fake. Written
/// by release.sh together with pubspec.yaml.
const appVersion = '0.5.0';
