import Flutter
import UIKit
import WebKit
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

/// Native half of the `mv2/web_cookies` channel (Dart:
/// `lib/core/network/web_cookie_bridge.dart`).
///
/// Lives in this file rather than its own because the Runner target uses a
/// classic pbxproj file list — a new .swift file would need project surgery.
///
/// Google OAuth finishes inside the in-app WKWebView, where the session cookie
/// (`PB3_SESSION`) is HttpOnly and therefore invisible to JavaScript. Dart
/// asks this bridge for the raw Cookie header straight from the shared
/// `WKWebsiteDataStore` — the same store `webview_flutter` writes to — and
/// seeds it into the Dio cookie jar.
final class WebCookieBridge {
  static let shared = WebCookieBridge()
  private static let channelName = "mv2/web_cookies"

  private init() {}

  func configure(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getCookies":
        guard
          let arguments = call.arguments as? [String: Any],
          let target = arguments["url"] as? String,
          let url = URL(string: target),
          let host = url.host
        else {
          result(
            FlutterError(
              code: "bad-arguments",
              message: "getCookies expects {url}",
              details: nil
            )
          )
          return
        }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
          // Same filter Android's CookieManager.getCookie applies: only the
          // cookies the target host would send (v2ex.com, incl. subdomains).
          let header = cookies
            .filter { cookie in
              cookie.domain.hasSuffix(host) || host.hasSuffix(cookie.domain)
            }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
          result(header)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
