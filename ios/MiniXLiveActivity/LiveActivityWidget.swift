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
// UI audit 2026-11-06 (Claude P2-5/P3-3, Codex P2-26): the accent
// purple on the near-black activity tint reads at about 3.8:1, too
// low for the small percent text, and Done/Failed were styled
// identically. Status text now uses high-contrast colors and each
// state gets its own icon.
private let doneColor = Color(red: 0.29, green: 0.87, blue: 0.5)
private let failedColor = Color(red: 0.97, green: 0.44, blue: 0.44)

private func stateIcon(_ state: MiniXDownloadAttributes.ContentState) -> String {
  if state.state == "done" { return "checkmark.circle.fill" }
  if state.state == "failed" { return "exclamationmark.triangle.fill" }
  return "arrow.down.circle.fill"
}

private func stateColor(_ state: MiniXDownloadAttributes.ContentState) -> Color {
  if state.state == "done" { return doneColor }
  if state.state == "failed" { return failedColor }
  return accent
}

private func percent(_ state: MiniXDownloadAttributes.ContentState) -> String {
  if state.state == "done" { return "Done" }
  if state.state == "failed" { return "Failed" }
  if state.progress < 0 { return "Starting" }
  return "\(Int((state.progress * 100).rounded()))%"
}

private func percentColor(_ state: MiniXDownloadAttributes.ContentState) -> Color {
  if state.state == "done" { return doneColor }
  if state.state == "failed" { return failedColor }
  return .white
}

private func detail(_ state: MiniXDownloadAttributes.ContentState) -> String {
  if state.state == "done" { return "Downloaded - ready in MiniX" }
  if state.state == "failed" { return "Download failed" }
  if state.totalGb > 0 {
    return String(
      format: "%.2f of %.2f GB", state.receivedGb, state.totalGb)
  }
  return "Starting download"
}

struct MiniXDownloadLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MiniXDownloadAttributes.self) { context in
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 6) {
          Image(systemName: stateIcon(context.state))
            .foregroundStyle(stateColor(context.state))
          Text(context.attributes.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer()
          Text(percent(context.state))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(percentColor(context.state))
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
      .widgetURL(URL(string: "minix://models"))
      .activityBackgroundTint(Color.black.opacity(0.88))
      .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label("MiniX", systemImage: stateIcon(context.state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(stateColor(context.state))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(percent(context.state))
            .font(.headline)
            .foregroundStyle(percentColor(context.state))
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
        Image(systemName: stateIcon(context.state))
          .foregroundStyle(stateColor(context.state))
      } compactTrailing: {
        Text(percent(context.state))
          .font(.caption.weight(.bold))
          .foregroundStyle(percentColor(context.state))
      } minimal: {
        Image(systemName: stateIcon(context.state))
          .foregroundStyle(stateColor(context.state))
      }
      .keylineTint(accent)
      .widgetURL(URL(string: "minix://models"))
    }
  }
}

@main
struct MiniXLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    MiniXDownloadLiveActivity()
  }
}
