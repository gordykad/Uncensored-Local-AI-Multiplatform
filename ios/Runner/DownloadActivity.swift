import ActivityKit
import Foundation

/// Ticket 23: Live Activity attributes for a model download. The
/// widget extension carries an identical copy of this struct; the
/// two processes decode each other's states, so the shapes must
/// never drift.
struct MiniXDownloadAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// 0...1, or -1 while the total size is unknown.
    var progress: Double
    var receivedGb: Double
    var totalGb: Double
    /// downloading | done | failed
    var state: String
  }

  var name: String
}

/// Starts, updates and ends download Live Activities from the
/// native download engine's own transition points (MiniXDownloads),
/// so the lock screen stays truthful even while the app is
/// suspended and Dart is asleep.
final class MiniXLiveActivity {
  static let shared = MiniXLiveActivity()
  private var activities: [String: Activity<MiniXDownloadAttributes>] = [:]
  private var lastProgress: [String: Double] = [:]
  private init() {}

  func started(filename: String, name: String) {
    finished(filename: filename, ok: false, cancelled: true)
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = MiniXDownloadAttributes.ContentState(
      progress: -1, receivedGb: 0, totalGb: 0, state: "downloading")
    do {
      let act = try Activity.request(
        attributes: MiniXDownloadAttributes(name: name),
        contentState: state,
        pushType: nil)
      activities[filename] = act
      lastProgress[filename] = -1
    } catch {
      // No activity, no problem: the notification still lands.
    }
  }

  func progress(filename: String, received: Int64, total: Int64) {
    guard let act = activities[filename] else { return }
    let p = total > 0 ? Double(received) / Double(total) : -1
    if p >= 0, let last = lastProgress[filename], p - last < 0.02 { return }
    lastProgress[filename] = p
    let state = MiniXDownloadAttributes.ContentState(
      progress: p,
      receivedGb: Double(received) / 1_073_741_824.0,
      totalGb: Double(total) / 1_073_741_824.0,
      state: "downloading")
    Task { await act.update(using: state) }
  }

  func finished(filename: String, ok: Bool, cancelled: Bool = false) {
    guard let act = activities.removeValue(forKey: filename) else { return }
    lastProgress.removeValue(forKey: filename)
    if cancelled {
      let state = MiniXDownloadAttributes.ContentState(
        progress: -1, receivedGb: 0, totalGb: 0, state: "failed")
      Task { await act.end(using: state, dismissalPolicy: .immediate) }
      return
    }
    // Dismissal: .default lets the finished card linger until the
    // system clears it. (The timed .after(Date) dismissal policy
    // is iOS 17+; the 16.x enum carries only .default/.immediate.)
    let state = MiniXDownloadAttributes.ContentState(
      progress: ok ? 1 : -1,
      receivedGb: 0, totalGb: 0,
      state: ok ? "done" : "failed")
    Task { await act.end(using: state, dismissalPolicy: .default) }
  }
}
