import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Diagnostics only — surface WHY APNs registration produced no token. The FCM
  // plugin auto-calls registerForRemoteNotifications but only NSLogs any failure
  // (invisible in a distributed build). Record the outcome where
  // shared_preferences can read it (it prefixes keys with "flutter."), shown on
  // the connection-test screen. Always call super so Firebase's AppDelegate
  // swizzling still forwards the token / failure.
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    UserDefaults.standard.set(
      "FAILED: \(error.localizedDescription)", forKey: "flutter.apnsRegStatus")
    super.application(
      application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    UserDefaults.standard.set(
      "registered OK (\(deviceToken.count) bytes)", forKey: "flutter.apnsRegStatus")
    super.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
