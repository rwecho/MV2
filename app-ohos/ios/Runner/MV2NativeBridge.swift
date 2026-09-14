import Flutter
import UIKit
import WidgetKit

/// Native half of the MV2 ↔ iOS integration.
///
/// Two jobs, both on one channel (`mv2/native`):
///
/// * **Home Screen quick actions** — the static items in `Info.plist` carry a
///   `route` in their `userInfo`; tapping one hands that route to Dart, which
///   navigates with go_router. A cold-launch tap arrives before Dart is
///   listening, so it is buffered until `consumePendingQuickAction` asks for it.
/// * **Widget snapshot** — Dart posts a small JSON document which is written to
///   the shared App Group container; the `MV2Widget` extension only reads it.
///   The extension never talks to the network or sees cookies.
///
/// Keep the App Group id in sync with `MV2Widget/MV2Widget.entitlements` and
/// `lib/core/native/mv2_native_bridge.dart`.
final class MV2NativeBridge {
  static let shared = MV2NativeBridge()

  static let appGroupId = "group.tech.zb.v2ex.maui.app"
  static let snapshotKey = "mv2.widget.snapshot"
  private static let channelName = "mv2/native"

  private var channel: FlutterMethodChannel?

  /// A shortcut tapped before Dart registered its handler (cold start).
  private var pendingQuickAction: String?

  private init() {}

  func configure(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  /// Entry point for both `willConnectTo` (cold) and `performActionFor` (warm).
  func handleQuickAction(route: String?) {
    guard let route, !route.isEmpty else { return }
    pendingQuickAction = route
    channel?.invokeMethod("quickAction", arguments: ["route": route])
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setWidgetSnapshot":
      guard let payload = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "bad-arguments",
            message: "setWidgetSnapshot expects a map",
            details: nil
          )
        )
        return
      }
      writeSnapshot(payload)
      reloadWidgets()
      result(nil)

    case "reloadWidgets":
      reloadWidgets()
      result(nil)

    case "consumePendingQuickAction":
      let route = pendingQuickAction
      pendingQuickAction = nil
      result(route)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func writeSnapshot(_ payload: [String: Any]) {
    guard
      let defaults = UserDefaults(suiteName: Self.appGroupId),
      let data = try? JSONSerialization.data(withJSONObject: payload)
    else { return }
    defaults.set(data, forKey: Self.snapshotKey)
  }

  private func reloadWidgets() {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
