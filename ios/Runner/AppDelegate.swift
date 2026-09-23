import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeApplicationSupportFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Keeps the database out of the iCloud backup.
  ///
  /// It lives in the application support directory, which iOS would otherwise
  /// upload; the app promises the data stays on the device. The flag sits on
  /// the directory rather than the file because it has to be set before drift
  /// creates the database, and it is set on every launch because a restored
  /// or migrated container does not carry it. Moving to a new phone directly
  /// is unaffected: that transfer copies excluded files too.
  private func excludeApplicationSupportFromBackup() {
    let manager = FileManager.default
    guard
      var directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return }
    try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? directory.setResourceValues(values)
  }
}
