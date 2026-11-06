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
/// native download engine's own transition points (MiniXDownloads).
/// Scope, stated plainly: the card updates while the process is
/// alive (foreground or background-run); while the app is fully
/// suspended no delegate callbacks fire and pushType is nil, so
/// the card freezes - completion still lands through the finish
/// notification when the system wakes the app for the transfer.
///
/// Threading: URLSession delegate callbacks arrive on concurrent
/// queues while start/cancel arrive on the main thread, so every
/// dictionary touch is serialized on `queue` (Claude audit).
final class MiniXLiveActivity {
  static let shared = MiniXLiveActivity()
  private let queue = DispatchQueue(label: "ai.minix.liveactivity")
  private var activities: [String: Activity<MiniXDownloadAttributes>] = [:]
  private var lastProgress: [String: Double] = [:]
  private var lastUpdateAt: [String: Date] = [:]
  private init() {}

  /// At launch: end any activity the previous process left on the
  /// lock screen. A still-running transfer recreates its card on
  /// the next progress callback (see progress()).
  func endAllStale() {
    Task {
      for act in Activity<MiniXDownloadAttributes>.activities {
        await act.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

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
      queue.sync {
        activities[filename] = act
        lastProgress[filename] = -1
        lastUpdateAt[filename] = Date()
      }
    } catch {
      // No activity, no problem: the notification still lands.
    }
  }

  func progress(filename: String, received: Int64, total: Int64) {
    let act: Activity<MiniXDownloadAttributes>? = queue.sync { activities[filename] }
    guard let act else {
      // Relaunch/jetsam orphaned this transfer's card; recreate
      // it instead of leaving the lock screen stale forever.
      started(filename: filename, name: filename)
      return
    }
    let p = total > 0 ? Double(received) / Double(total) : -1
    let pass: Bool = queue.sync {
      if p >= 0, let last = lastProgress[filename], p - last < 0.02 {
        return false
      }
      // Unknown totals get a time throttle instead of the 2% step.
      if p < 0, let at = lastUpdateAt[filename],
         Date().timeIntervalSince(at) < 0.5 {
        return false
      }
      lastProgress[filename] = p
      lastUpdateAt[filename] = Date()
      return true
    }
    guard pass else { return }
    let state = MiniXDownloadAttributes.ContentState(
      progress: p,
      receivedGb: Double(received) / 1_073_741_824.0,
      totalGb: Double(total) / 1_073_741_824.0,
      state: "downloading")
    Task { await act.update(using: state) }
  }

  func finished(filename: String, ok: Bool, cancelled: Bool = false) {
    let act: Activity<MiniXDownloadAttributes>? = queue.sync {
      lastProgress.removeValue(forKey: filename)
      lastUpdateAt.removeValue(forKey: filename)
      return activities.removeValue(forKey: filename)
    }
    guard let act else { return }
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
