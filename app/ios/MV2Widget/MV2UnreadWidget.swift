import SwiftUI
import WidgetKit

/// Timeline plumbing shared by the Home Screen and Lock Screen widgets.
struct MV2Entry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot
}

struct MV2Provider: TimelineProvider {
  func placeholder(in context: Context) -> MV2Entry {
    MV2Entry(date: Date(), snapshot: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (MV2Entry) -> Void
  ) {
    completion(
      MV2Entry(date: Date(), snapshot: context.isPreview ? .placeholder : .load())
    )
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<MV2Entry>) -> Void
  ) {
    let entry = MV2Entry(date: Date(), snapshot: .load())
    // The app calls `WidgetCenter.reloadAllTimelines()` whenever the snapshot
    // changes; the hourly floor only keeps the "更新于" line honest.
    let next = Date().addingTimeInterval(60 * 60)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

/// Home Screen widget: unread count, plus the latest notifications in the
/// medium size. Read-only on purpose — a write action would need the session's
/// CSRF `once` token, which the extension deliberately cannot see.
struct MV2UnreadWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MV2UnreadWidget", provider: MV2Provider()) { entry in
      MV2UnreadView(entry: entry)
    }
    .configurationDisplayName("V2EX 通知")
    .description("未读通知数量与最近几条回复。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct MV2UnreadView: View {
  @Environment(\.widgetFamily) private var family
  let entry: MV2Entry

  var body: some View {
    Group {
      if !entry.snapshot.signedIn {
        signedOut
      } else if family == .systemMedium {
        medium
      } else {
        small
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }

  private var signedOut: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("MV2")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text("登录后查看通知")
        .font(.headline)
      Spacer()
    }
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("MV2")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text("\(entry.snapshot.unread)")
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .minimumScaleFactor(0.5)
      Text(entry.snapshot.unread == 0 ? "没有未读" : "条未读")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text(entry.snapshot.updatedDate, style: .relative)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
  }

  private var medium: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("未读")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("\(entry.snapshot.unread)")
          .font(.system(size: 36, weight: .semibold, design: .rounded))
          .minimumScaleFactor(0.5)
        Spacer()
        Text(entry.snapshot.updatedDate, style: .relative)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .frame(width: 64, alignment: .leading)

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        if entry.snapshot.items.isEmpty {
          Text("打开通知页后这里会显示最近回复")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(entry.snapshot.items.prefix(3)) { item in
            VStack(alignment: .leading, spacing: 1) {
              Text(item.actor)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
              Text(item.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}
