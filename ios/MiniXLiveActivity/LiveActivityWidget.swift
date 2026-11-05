import ActivityKit
import SwiftUI
import WidgetKit

/// Identical copy of the app's attributes struct (the extension is
/// a separate process; ActivityKit matches by shape).
struct MiniXDownloadAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var progress: Double
    var receivedGb: Double
    var totalGb: Double
    var state: String
  }

  var name: String
}

private let accent = Color(red: 0.576, green: 0.2, blue: 0.918)

private func percent(_ state: MiniXDownloadAttributes.ContentState) -> String {
  if state.state == "done" { return "Done" }
  if state.state == "failed" { return "Failed" }
  if state.progress < 0 { return "..." }
  return "\(Int((state.progress * 100).rounded()))%"
}

private func detail(_ state: MiniXDownloadAttributes.ContentState) -> String {
  if state.state == "done" { return "Downloaded - ready in MiniX" }
  if state.state == "failed" { return "Download failed" }
  if state.totalGb > 0 {
    return String(
      format: "%.2f of %.2f GB", state.receivedGb, state.totalGb)
  }
  return "Downloading..."
}

struct MiniXDownloadLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MiniXDownloadAttributes.self) { context in
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 6) {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(accent)
          Text(context.attributes.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer()
          Text(percent(context.state))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(accent)
        }
        if context.state.progress >= 0 {
          ProgressView(value: context.state.progress)
            .tint(accent)
        } else {
          ProgressView().tint(accent)
        }
        Text(detail(context.state))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(14)
      .activityBackgroundTint(Color.black.opacity(0.88))
      .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("MiniX", systemImage: "arrow.down.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(percent(context.state))
            .font(.headline)
            .foregroundStyle(accent)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 5) {
            Text(context.attributes.name)
              .font(.caption)
              .lineLimit(1)
            if context.state.progress >= 0 {
              ProgressView(value: context.state.progress).tint(accent)
            } else {
              ProgressView().tint(accent)
            }
            Text(detail(context.state))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
      } compactTrailing: {
        Text(percent(context.state))
          .font(.caption.weight(.bold))
          .foregroundStyle(accent)
      } minimal: {
        Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
      }
      .keylineTint(accent)
    }
  }
}

@main
struct MiniXLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    MiniXDownloadLiveActivity()
  }
}
