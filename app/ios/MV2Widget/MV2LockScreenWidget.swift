import SwiftUI
import WidgetKit

/// Lock Screen widgets: the same snapshot, in the three accessory families.
struct MV2LockScreenWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MV2LockScreenWidget", provider: MV2Provider()) {
      entry in
      MV2LockScreenView(entry: entry)
    }
    .configurationDisplayName("V2EX 未读")
    .description("锁屏上的未读数量与最新一条回复。")
    .supportedFamilies([
      .accessoryCircular,
      .accessoryRectangular,
      .accessoryInline,
    ])
  }
}

struct MV2LockScreenView: View {
  @Environment(\.widgetFamily) private var family
  let entry: MV2Entry

  var body: some View {
    if !entry.snapshot.signedIn {
      Text("MV2 · 未登录")
    } else {
      switch family {
      case .accessoryCircular:
        Gauge(value: Double(min(entry.snapshot.unread, 99)), in: 0...99) {
          Image(systemName: "bell")
        } currentValueLabel: {
          Text("\(entry.snapshot.unread)")
        }
        .gaugeStyle(.accessoryCircular)

      case .accessoryRectangular:
        VStack(alignment: .leading, spacing: 1) {
          Text("V2EX · \(entry.snapshot.unread) 条未读")
            .font(.headline)
          if let first = entry.snapshot.items.first {
            Text("\(first.actor)：\(first.text)")
              .font(.caption)
              .lineLimit(2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

      default:
        Text("V2EX · \(entry.snapshot.unread) 条未读")
      }
    }
  }
}
