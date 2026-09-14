import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  /// Cold launch from a Home Screen quick action: the Flutter engine is not up
  /// yet, so `MV2NativeBridge` buffers the route until Dart asks for it.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let shortcut = connectionOptions.shortcutItem {
      MV2NativeBridge.shared.handleQuickAction(route: shortcut.routeValue)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  /// Warm tap while the app is already running.
  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    MV2NativeBridge.shared.handleQuickAction(route: shortcutItem.routeValue)
    completionHandler(true)
  }
}

private extension UIApplicationShortcutItem {
  /// The go_router path the static `Info.plist` item declares.
  var routeValue: String? {
    userInfo?["route"] as? String
  }
}
