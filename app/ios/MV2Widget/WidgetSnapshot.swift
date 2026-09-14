import Foundation

/// The snapshot the app publishes into the shared App Group container.
///
/// Mirrors `lib/core/native/widget_snapshot.dart` field for field — the widget
/// extension has no network access and no credentials, it only draws what the
/// app last fetched.
struct WidgetSnapshot: Codable {
  struct Item: Codable, Identifiable {
    let actor: String
    let text: String
    let topicId: Int?

    var id: String { "\(actor)|\(text)" }
  }

  let unread: Int
  let updatedAt: Int
  let signedIn: Bool
  let items: [Item]

  static let placeholder = WidgetSnapshot(
    unread: 3,
    updatedAt: Int(Date().timeIntervalSince1970 * 1000),
    signedIn: true,
    items: [
      Item(actor: "sentinelK", text: "没有列全部的具体数据，但列了一些例子。", topicId: 1),
      Item(actor: "Livid", text: "V2EX 是一个关于分享和探索的地方。", topicId: 2),
    ]
  )

  static let signedOut = WidgetSnapshot(
    unread: 0,
    updatedAt: 0,
    signedIn: false,
    items: []
  )

  /// Keep in sync with `MV2NativeBridge.appGroupId` / `.snapshotKey`.
  static let appGroupId = "group.tech.zb.v2ex.maui.app"
  static let snapshotKey = "mv2.widget.snapshot"

  static func load() -> WidgetSnapshot {
    guard
      let defaults = UserDefaults(suiteName: appGroupId),
      let data = defaults.data(forKey: snapshotKey),
      let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    else { return .signedOut }
    return snapshot
  }

  var updatedDate: Date {
    Date(timeIntervalSince1970: Double(updatedAt) / 1000)
  }
}
