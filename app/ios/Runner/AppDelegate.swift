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
    // Application-level channel for quick actions and the widget snapshot.
    MV2NativeBridge.shared.configure(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    // Cookie harvest for the in-app-WebView Google OAuth login.
    WebCookieBridge.shared.configure(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    // Prompt-free clipboard probing for the V2EX-link detection.
    ClipboardProbeBridge.shared.configure(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
